/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2016 - 2018 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 *
 *  * Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 *  * Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 *  * Neither the name of Textual, "Codeux Software, LLC", nor the
 *    names of its contributors may be used to endorse or promote products
 *    derived from this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED. IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
 * FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
 * OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
 * LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
 * OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
 * SUCH DAMAGE.
 *
 *********************************************************************** */

import CoreData
import Foundation
import os

/// One FIFO lane owns the root transaction and every view's counters. An await
/// may let another caller enqueue work, but never enter an in-flight transaction.
actor HistoricLogStore {
	typealias DeletionHandler = @Sendable ([String], String) async -> Void
	typealias StackFactory = @Sendable (URL) throws -> NSManagedObjectContext
	/** How long a scheduled retention pass waits before it runs. Spread over
	 half an hour in production so a launch that opens many views does not stop
	 to prune all of them at once; a test substitutes a fixed value. */
	typealias ResizeDelay = @Sendable () -> Duration

	private enum Lifecycle { case closed, open, closing }
	private struct ViewState {
		var generation = UUID()
		var totalLineCount: UInt
		var maximumIdentifier: UInt
		var resizeTask: Task<Void, Never>?
	}

	private var lifecycle = Lifecycle.closed
	private var occupied = false
	private var closingCount = 0
	private var waiting: [CheckedContinuation<Void, Never>] = []
	private var context: NSManagedObjectContext?
	private var databaseURL: URL?
	private var views: [String: ViewState] = [:]
	private var maximumLineCount: UInt = 100
	private var saveTask: Task<Void, Never>?
	private let filenameStore: any HistoricLogFilenameStoring
	private let deletionHandler: DeletionHandler
	private let makeStack: StackFactory
	private let resizeDelay: ResizeDelay
	private let willPerform: (@Sendable (HistoricLogStoreOperation) async -> Void)?
	var pendingOperationCount: Int {
		waiting.count
	}

	init(
		filenameStore: any HistoricLogFilenameStoring,
		makeStack: @escaping StackFactory = { try HistoricLogDatabase.makeStack(at: $0) },
		resizeDelay: @escaping ResizeDelay = { .seconds(Int.random(in: 0 ..< 1800)) },
		willPerform: (@Sendable (HistoricLogStoreOperation) async -> Void)? = nil,
		deletionHandler: @escaping DeletionHandler = { _, _ in }
	) {
		self.filenameStore = filenameStore
		self.makeStack = makeStack
		self.resizeDelay = resizeDelay
		self.willPerform = willPerform
		self.deletionHandler = deletionHandler
	}

	private func enter() async {
		if occupied {
			await withCheckedContinuation { waiting.append($0) }
		} else {
			occupied = true
		}
	}

	private func leave() {
		if waiting.isEmpty {
			occupied = false
		} else {
			waiting.removeFirst().resume()
		}
	}

	func openDatabase(inDirectory directory: String) async -> HistoricLogOpenOutcome {
		await enter()
		defer { leave() }
		let filename: String
		if let saved = filenameStore.databaseFilename {
			filename = saved
		} else {
			filename = "logControllerHistoricLog_\(UUID().uuidString).sqlite"
			filenameStore.databaseFilename = filename
		}
		let url = URL(fileURLWithPath: directory, isDirectory: true).appendingPathComponent(filename)
		if let databaseURL, context != nil, databaseURL != url {
			return .failed(reason: CocoaError(.persistentStoreOperation).localizedDescription)
		}
		do {
			if context == nil {
				context = try makeStack(url)
			}
			guard let context else { return .failed(reason: nil) }
			databaseURL = url
			let outcome = await context.perform {
				context.retainsRegisteredObjects = false
				return HistoricLogDatabase.restampEntryCreationDates(in: context)
			}
			guard case .saved = outcome else {
				if case let .failed(reason) = outcome {
					return .failed(reason: reason)
				}
				return .failed(reason: nil)
			}
			lifecycle = closingCount == 0 ? .open : .closing
			scheduleSave()
			return .opened
		} catch { return .failed(reason: error.localizedDescription) }
	}

	@discardableResult
	func close() async -> HistoricLogSaveOutcome {
		// Close admission immediately. Writes already in the FIFO still get their turn.
		lifecycle = .closing
		closingCount += 1
		saveTask?.cancel()
		saveTask = nil
		await enter()
		defer { closingCount -= 1; leave() }
		await willPerform?(.close)
		for state in views.values {
			state.resizeTask?.cancel()
		}
		guard let context else { lifecycle = .closed; return .saved }
		let outcome = await context.perform { HistoricLogDatabase.quickSave(context) }
		switch outcome {
		case .saved:
			views.removeAll()
			self.context = nil
			lifecycle = .closed
		case .failed:
			// No reset: unsaved objects remain available to saveData or a later close.
			lifecycle = closingCount == 1 ? .open : .closing
			for identifier in views.keys {
				views[identifier]?.resizeTask = nil
			}
		}
		return outcome
	}

	func setMaximumLineCount(_ count: UInt) {
		guard count > 0 else { return }
		let lowered = count < maximumLineCount
		maximumLineCount = count
		for identifier in views.keys {
			/* A pass already waiting was armed for the old limit and may not be
			 due for another half hour. Retiring it is what lets the new limit
			 arm a pass of its own. */
			if lowered {
				views[identifier]?.resizeTask?.cancel()
				views[identifier]?.resizeTask = nil
			}
			scheduleResize(identifier)
		}
	}

	private func initializeView(_ identifier: String, in context: NSManagedObjectContext) async throws {
		guard views[identifier] == nil else { return }
		let counts = try await context.perform {
			try HistoricLogDatabase.initialCounts(in: context, viewIdentifier: identifier)
		}
		views[identifier] = ViewState(totalLineCount: counts.lineCount, maximumIdentifier: counts.maximumIdentifier)
	}

	@discardableResult
	func writeLogLine(_ entry: HistoricLogEntry) async -> HistoricLogWriteOutcome {
		guard lifecycle == .open else { return .unavailable }
		await enter()
		defer { leave() }
		await willPerform?(.write)
		guard let context else { return .unavailable }
		do {
			try await initializeView(entry.viewIdentifier, in: context)
			guard let state = views[entry.viewIdentifier], state.maximumIdentifier < UInt(Int64.max) else {
				return .failed(CocoaError(.validationNumberTooLarge).localizedDescription)
			}
			let next = state.maximumIdentifier + 1
			let inserted = await context
				.perform { HistoricLogDatabase.insert(entry, in: context, entryIdentifier: next) }
			guard inserted else { return .failed(CocoaError(.persistentStoreOperation).localizedDescription) }
			views[entry.viewIdentifier]?.maximumIdentifier = next
			views[entry.viewIdentifier]?.totalLineCount = saturatedAdd(state.totalLineCount, 1)
			scheduleResize(entry.viewIdentifier)
			return .accepted
		} catch { return .failed(error.localizedDescription) }
	}

	@discardableResult
	func forgetView(_ identifier: String) async -> HistoricLogDeletionOutcome {
		await removeHistory(identifier, forget: true)
	}

	@discardableResult
	func resetData(forView identifier: String) async -> HistoricLogDeletionOutcome {
		await removeHistory(identifier, forget: false)
	}

	private func removeHistory(_ identifier: String, forget: Bool) async -> HistoricLogDeletionOutcome {
		guard lifecycle == .open else { return .unavailable }
		await enter()
		defer { leave() }
		await willPerform?(forget ? .forget : .reset)
		guard let context else { return .unavailable }
		let outcome = await context.perform {
			HistoricLogDatabase.deleteOutcome(.everything, in: context, viewIdentifier: identifier)
		}
		if case let .deleted(result) = outcome {
			views[identifier]?.resizeTask?.cancel()
			if forget {
				views.removeValue(forKey: identifier)
			} else {
				views[identifier]?.generation = UUID()
				views[identifier]?.totalLineCount = 0
				views[identifier]?.resizeTask = nil
			}
			// The one-way notification completes before a newer view generation can enter.
			if !result.uniqueIdentifiers.isEmpty {
				await deletionHandler(result.uniqueIdentifiers, identifier)
			}
		}
		return outcome
	}

	func fetchEntries(forView identifier: String, ascending: Bool, fetchLimit: UInt,
	                  limitToDate: Date?) async -> [HistoricLogEntry]
	{
		await fetchOutcome(HistoricLogFetchRequest(
			viewIdentifier: identifier,
			kind: .newest(ascending: ascending, fetchLimit: fetchLimit, limitToDate: limitToDate)
		)).entries
	}

	func fetchEntries(forView identifier: String, before line: String, fetchLimit: UInt,
	                  limitToDate: Date?) async -> [HistoricLogEntry]
	{
		await fetchOutcome(HistoricLogFetchRequest(
			viewIdentifier: identifier,
			kind: .before(uniqueIdentifier: line, fetchLimit: fetchLimit, limitToDate: limitToDate)
		)).entries
	}

	func fetchOutcome(_ request: HistoricLogFetchRequest) async -> HistoricLogFetchOutcome {
		guard !Task.isCancelled else { return .cancelled }
		guard lifecycle == .open else { return .failed(.unavailable) }
		await enter()
		defer { leave() }
		guard !Task.isCancelled else { return .cancelled }
		guard let context else { return .failed(.unavailable) }
		do {
			try await initializeView(request.viewIdentifier, in: context)
		} catch {
			return .failed(.read(error.localizedDescription))
		}
		let outcome = await context.perform {
			switch request.kind {
			case let .newest(ascending, limit, date):
				HistoricLogDatabase.fetchOutcome(
					in: context,
					viewIdentifier: request.viewIdentifier,
					ascending: ascending,
					fetchLimit: limit,
					limitToDate: date
				)
			case let .before(line, limit, date):
				HistoricLogDatabase.fetchOutcome(in: context, viewIdentifier: request.viewIdentifier, before: line,
				                                 fetchLimit: limit, limitToDate: date)
			case let .rowPage(cursor, limit, date):
				HistoricLogDatabase.fetchRowPage(in: context, viewIdentifier: request.viewIdentifier, before: cursor,
				                                 fetchLimit: limit, limitToDate: date)
			}
		}
		return Task.isCancelled ? .cancelled : outcome
	}

	@discardableResult
	func saveData() async -> HistoricLogSaveOutcome {
		guard lifecycle == .open else { return .failed(CocoaError(.persistentStoreOperation).localizedDescription) }
		await enter()
		defer { leave() }
		await willPerform?(.save)
		guard let context else { return .failed(CocoaError(.persistentStoreOperation).localizedDescription) }
		return await context.perform { HistoricLogDatabase.quickSave(context) }
	}

	private func scheduleSave() {
		guard saveTask == nil else { return }
		saveTask = Task { [weak self] in
			while !Task.isCancelled {
				try? await Task.sleep(for: .seconds(120))
				guard !Task.isCancelled, let self else { return }
				_ = await saveData()
			}
		}
	}

	private func scheduleResize(_ identifier: String) {
		guard lifecycle == .open, let state = views[identifier], state.resizeTask == nil,
		      state.totalLineCount > maximumLineCount else { return }
		let delay = resizeDelay()
		views[identifier]?.resizeTask = Task { [weak self] in
			try? await Task.sleep(for: delay)
			guard !Task.isCancelled else { return }
			_ = await self?.resize(identifier, generation: state.generation)
		}
	}

	/** Hands the view's scheduled-pass slot back, so a later pass can be armed.

	 The slot is the only thing ``scheduleResize`` checks before it arms one, so
	 a pass that returns without releasing it leaves the view over its limit
	 until something else replaces the whole view state. A newer generation owns
	 its own slot and must not have it cleared from under it. */
	private func releaseResizeSlot(_ identifier: String, generation: UUID?) {
		guard generation == nil || generation == views[identifier]?.generation else { return }
		views[identifier]?.resizeTask = nil
	}

	@discardableResult
	func resize(_ identifier: String, generation: UUID? = nil) async -> HistoricLogDeletionOutcome {
		guard lifecycle == .open else { return .unavailable }
		await enter()
		defer { leave() }
		await willPerform?(.resize)
		guard !Task.isCancelled, generation == nil || generation == views[identifier]?.generation,
		      let context
		else {
			releaseResizeSlot(identifier, generation: generation)
			return .unavailable
		}
		let limit = maximumLineCount
		let outcome = await context.perform {
			HistoricLogDatabase.deleteOutcome(.retainingNewest(count: limit), in: context, viewIdentifier: identifier)
		}
		releaseResizeSlot(identifier, generation: generation)
		if case let .deleted(result) = outcome, result.deletedCount > 0 {
			if let count = views[identifier]?.totalLineCount {
				views[identifier]?.totalLineCount = count - min(count, result.deletedCount)
			}
			if !result.uniqueIdentifiers.isEmpty {
				await deletionHandler(result.uniqueIdentifiers, identifier)
			}
			/* One pass may leave the view over its limit — the limit can have been
			 lowered again while this one ran. A pass that deleted nothing arms no
			 successor, so a counter that disagrees with the store cannot spin. */
			scheduleResize(identifier)
		}
		return outcome
	}
}

nonisolated func saturatedAdd(_ lhs: UInt, _ rhs: UInt) -> UInt { // nonisolated: pure
	let (result, overflow) = lhs.addingReportingOverflow(rhs)
	return overflow ? UInt.max : result
}

nonisolated enum HistoricLogOpenOutcome: Sendable { // nonisolated: value
	case opened
	case failed(reason: String?)
	var isOpen: Bool {
		if case .opened = self {
			true
		} else {
			false
		}
	}
}
