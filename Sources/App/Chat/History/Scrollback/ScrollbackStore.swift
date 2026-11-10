// Copyright (c) 2016 - 2018 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CoreData
import Foundation
import os

/// The transaction the store is about to run, for a test that has to hold one
/// in flight. Nothing in the app observes it.
nonisolated enum ScrollbackStoreOperation: Equatable, Sendable {
	case open, write, reset, forget, close, save, resize, fetch, search
}

/** The Core Data transaction, and every view's counters.

 One caller at a time holds it: an await inside an operation may let another
 enqueue work, but never enter a transaction that is in flight. That is the whole
 of what this type serializes — the order the work was asked for is
 ``ScrollbackSession``'s, which is the only thing above it. */
actor ScrollbackStore {
	typealias DeletionHandler = @Sendable ([String], String) async -> Void
	/// Told why a save the store made on its own did not land.
	typealias SaveFailureHandler = @Sendable (String) async -> Void
	typealias MakeStack = @Sendable (URL) throws -> NSManagedObjectContext
	/** How long a scheduled retention pass waits before it runs. Spread over
	 half an hour in production so a launch that opens many views does not stop
	 to prune all of them at once; a test substitutes a fixed value. */
	typealias ResizeDelay = @Sendable () -> Duration

	private enum Lifecycle { case closed, open, closing }
	private struct ScheduledResize {
		let identifier: UUID
		let task: Task<Void, Never>
	}

	private struct BurstSave {
		let identifier: UUID
		let task: Task<Void, Never>
	}

	private struct ViewState {
		var totalLineCount: UInt
		var maximumIdentifier: UInt
		var resize: ScheduledResize?
	}

	private var lifecycle = Lifecycle.closed
	private var occupied = false
	private var closingCount = 0
	/** Operations queued behind the one in flight, oldest first. `waitingHead`
	 is the next to resume, so handing the store on is O(1) rather than the
	 shift `removeFirst` makes of every entry behind it. Every waiter is resumed
	 by ``leave()`` and each operation runs even for a cancelled caller, so
	 cancellation has nothing to remove and nothing to strand. */
	private var waiting: [CheckedContinuation<Void, Never>?] = []
	private var waitingHead = 0
	private var context: NSManagedObjectContext?
	private var databaseURL: URL?
	private var views: [String: ViewState] = [:]
	private var maximumLineCount: UInt = 100
	private var saveTask: Task<Void, Never>?
	/** The save armed by the rows written since the last one. It waits
	 `saveDelay` from the first of them, or runs at once when `saveRowThreshold`
	 of them have piled up. */
	private var burstSave: BurstSave?
	/** Rows inserted since a save was last attempted, whether or not it landed.
	 Counted from the attempt rather than the success, so a save that keeps
	 failing is retried when the next batch of rows or the next delay is up and
	 not on every row. */
	private var rowsSinceSave = 0
	private let filenameSetting: ScrollbackFilenameSetting
	private let deletionHandler: DeletionHandler
	private let saveFailureHandler: SaveFailureHandler
	private let makeStack: MakeStack
	private let resizeDelay: ResizeDelay
	/// How long the store waits between the saves it makes on its own. Writes
	/// arm earlier ones; this loop is the safety net for changes they do not
	/// count, such as a replacement or a redaction.
	private let saveInterval: Duration
	/** Unsaved rows are about 1.4 KB each in Core Data's registered objects, so
	 500 of them hold the pending cost to roughly 0.7 MB, and a save of that many
	 rows in WAL mode is a few milliseconds. */
	private let saveRowThreshold: Int
	/// The longest a written row waits for a save while traffic continues.
	private let saveDelay: Duration
	private let willPerform: (@Sendable (ScrollbackStoreOperation) async -> Void)?
	var pendingOperationCount: Int {
		waiting.count - waitingHead
	}

	init(
		filenameSetting: ScrollbackFilenameSetting,
		makeStack: MakeStack? = nil,
		migrationProgress: @escaping @Sendable (Double) -> Void = { _ in },
		resizeDelay: @escaping ResizeDelay = { .seconds(Int.random(in: 0 ..< 1800)) },
		saveInterval: Duration = .seconds(120),
		saveRowThreshold: Int = 500,
		saveDelay: Duration = .seconds(5),
		willPerform: (@Sendable (ScrollbackStoreOperation) async -> Void)? = nil,
		saveFailureHandler: @escaping SaveFailureHandler = { _ in },
		deletionHandler: @escaping DeletionHandler = { _, _ in }
	) {
		self.filenameSetting = filenameSetting
		self.makeStack = makeStack ?? { try ScrollbackQueries.makeStack(at: $0, migrationProgress: migrationProgress) }
		self.resizeDelay = resizeDelay
		self.saveInterval = saveInterval
		self.saveRowThreshold = max(1, saveRowThreshold)
		self.saveDelay = saveDelay
		self.willPerform = willPerform
		self.saveFailureHandler = saveFailureHandler
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
		guard waitingHead < waiting.count else {
			waiting.removeAll(keepingCapacity: true)
			waitingHead = 0
			occupied = false
			return
		}
		let next = waiting[waitingHead]
		waiting[waitingHead] = nil
		waitingHead += 1
		/* Reclaim the consumed prefix once it dominates, keeping the cost amortized O(1). */
		if waitingHead >= 32, waitingHead * 2 >= waiting.count {
			waiting.removeFirst(waitingHead)
			waitingHead = 0
		}
		next?.resume()
	}

	/** What a database this build minted is called.

	 The name is remembered in a setting, so it is only ever chosen once per
	 installation; a store written by any other schema keeps whatever it was
	 called and is simply never named by that setting again. */
	static let databaseFilenamePrefix = "Scrollback_"

	func openDatabase(inDirectory directory: String) async -> ScrollbackOpenOutcome {
		await enter()
		defer { leave() }
		let filename: String
		if let saved = filenameSetting.load() {
			filename = saved
		} else {
			filename = "\(Self.databaseFilenamePrefix)\(UUID().uuidString).sqlite"
			filenameSetting.save(filename)
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
			await context.perform { context.retainsRegisteredObjects = false }
			await willPerform?(.open)
			lifecycle = closingCount == 0 ? .open : .closing
			scheduleSave()
			return .opened
		} catch { return .failed(reason: error.localizedDescription) }
	}

	@discardableResult
	func close() async -> ScrollbackSaveOutcome {
		// Close admission immediately. Writes already in the FIFO still get their turn.
		lifecycle = .closing
		closingCount += 1
		saveTask?.cancel()
		saveTask = nil
		burstSave?.task.cancel()
		burstSave = nil
		await enter()
		defer { closingCount -= 1; leave() }
		await willPerform?(.close)
		for state in views.values {
			state.resize?.task.cancel()
		}
		guard let context else { lifecycle = .closed; return .saved }
		let outcome = await commit(context)
		switch outcome {
		case .saved:
			views.removeAll()
			self.context = nil
			lifecycle = .closed
		case .failed:
			// No reset: unsaved objects remain available to saveData or a later close.
			lifecycle = closingCount == 1 ? .open : .closing
			for identifier in views.keys {
				views[identifier]?.resize = nil
			}
			/* Admission cancelled the periodic save. A store that stays open has
			 to keep saving on its own, or the rows the next writes add wait for a
			 close that may never come; a close still queued behind this one
			 already retired the loop again and owns what happens next. */
			if closingCount == 1 {
				scheduleSave()
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
				views[identifier]?.resize?.task.cancel()
				views[identifier]?.resize = nil
			}
			scheduleResize(identifier)
		}
	}

	private func initializeView(_ identifier: String, in context: NSManagedObjectContext) async throws {
		guard views[identifier] == nil else { return }
		let counts = try await context.perform {
			try ScrollbackQueries.initialCounts(in: context, viewIdentifier: identifier)
		}
		views[identifier] = ViewState(totalLineCount: counts.lineCount, maximumIdentifier: counts.maximumIdentifier)
		scheduleResize(identifier)
	}

	@discardableResult
	func writeChatLine(_ entry: ScrollbackEntry) async -> ScrollbackWriteOutcome {
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
				.perform { ScrollbackQueries.insert(entry, in: context, entryIdentifier: next) }
			guard inserted else { return .failed(CocoaError(.persistentStoreOperation).localizedDescription) }
			views[entry.viewIdentifier]?.maximumIdentifier = next
			views[entry.viewIdentifier]?.totalLineCount = saturatedAdd(state.totalLineCount, 1)
			noteInsertedRow()
			scheduleResize(entry.viewIdentifier)
			return .accepted
		} catch { return .failed(error.localizedDescription) }
	}

	func replaceChatLine(_ entry: ScrollbackEntry) async -> ScrollbackReplacementOutcome {
		guard lifecycle == .open else { return .unavailable }
		await enter()
		defer { leave() }
		guard let context else { return .unavailable }
		return await context.perform { ScrollbackQueries.replace(entry, in: context) }
	}

	func redactChatLine(
		messageIdentifier: String,
		inView viewIdentifier: String
	) async -> ScrollbackRedactionOutcome {
		guard lifecycle == .open else { return .unavailable }
		await enter()
		defer { leave() }
		guard let context else { return .unavailable }
		return await context.perform {
			ScrollbackQueries.redact(messageIdentifier: messageIdentifier, viewIdentifier: viewIdentifier, in: context)
		}
	}

	@discardableResult
	func forgetView(_ identifier: String) async -> ScrollbackDeletionOutcome {
		await removeHistory(identifier, forget: true)
	}

	@discardableResult
	func resetData(forView identifier: String) async -> ScrollbackDeletionOutcome {
		await removeHistory(identifier, forget: false)
	}

	private func removeHistory(_ identifier: String, forget: Bool) async -> ScrollbackDeletionOutcome {
		guard lifecycle == .open else { return .unavailable }
		await enter()
		defer { leave() }
		await willPerform?(forget ? .forget : .reset)
		guard let context else { return .unavailable }
		// A deletion saves what is pending before it deletes, and again after.
		rowsSinceSave = 0
		let outcome = await context.perform {
			ScrollbackQueries.deleteOutcome(.everything, in: context, viewIdentifier: identifier)
		}
		if case let .deleted(result) = outcome {
			views[identifier]?.resize?.task.cancel()
			if forget {
				views.removeValue(forKey: identifier)
			} else {
				views[identifier]?.totalLineCount = 0
				views[identifier]?.resize = nil
			}
			// The one-way notification completes before a newer view generation can enter.
			if !result.uniqueIdentifiers.isEmpty {
				await deletionHandler(result.uniqueIdentifiers, identifier)
			}
		}
		return outcome
	}

	func fetchOutcome(_ request: ScrollbackFetchRequest) async -> ScrollbackFetchOutcome {
		guard !Task.isCancelled else { return .cancelled }
		guard lifecycle == .open else { return .failed(.unavailable) }
		await enter()
		defer { leave() }
		await willPerform?(.fetch)
		guard !Task.isCancelled else { return .cancelled }
		guard let context else { return .failed(.unavailable) }
		do {
			try await initializeView(request.viewIdentifier, in: context)
		} catch {
			return .failed(.read(error.localizedDescription))
		}
		let outcome = await context.perform {
			switch request.kind {
			case let .before(line, limit, date):
				ScrollbackQueries.fetchOutcome(in: context, viewIdentifier: request.viewIdentifier, before: line,
				                               fetchLimit: limit, limitToDate: date)
			case let .rowPage(cursor, limit, date):
				ScrollbackQueries.fetchRowPage(in: context, viewIdentifier: request.viewIdentifier, before: cursor,
				                               fetchLimit: limit, limitToDate: date)
			case let .window(cursor, olderLimit, newerLimit):
				ScrollbackQueries.fetchWindow(in: context, viewIdentifier: request.viewIdentifier, around: cursor,
				                              olderLimit: olderLimit, newerLimit: newerLimit)
			}
		}
		return Task.isCancelled ? .cancelled : outcome
	}

	/** Searches the stored text of the views a query names, newest match first.

	 The store is held only to save what is pending and to read the database
	 once per view, never across the whole search: a reader context of its own
	 does the reading, so a long search over a large history does not keep
	 lines from being written. A search sees what has been saved, which is
	 everything accepted before it began. Cancelling the task stops it between
	 views. */
	func search(_ query: ScrollbackSearchQuery) async -> ScrollbackSearchOutcome {
		guard !Task.isCancelled else { return .cancelled }
		guard lifecycle == .open else { return .unavailable }
		await enter()
		await willPerform?(.search)
		guard let context else {
			leave()
			return .unavailable
		}
		let saved = await commit(context)
		leave()
		if case let .failed(reason) = saved {
			return .failed(reason)
		}

		let reader = await context.perform { () -> NSManagedObjectContext? in
			guard let coordinator = context.persistentStoreCoordinator else { return nil }
			let reader = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
			reader.persistentStoreCoordinator = coordinator
			reader.undoManager = nil
			return reader
		}
		guard let reader else { return .unavailable }
		let normalized = query.normalized
		var hits: [ScrollbackSearchHit] = []
		for view in normalized.viewIdentifiers {
			guard !Task.isCancelled else { return .cancelled }
			let found = await reader.perform {
				ScrollbackQueries.search(in: reader, viewIdentifier: view, query: normalized)
			}
			switch found {
			case let .success(rows): hits.append(contentsOf: rows)
			case let .failure(reason): return .failed(reason)
			}
		}
		hits.sort { $0.sortsBefore($1) }
		let truncated = hits.count > normalized.limit
		return .results(Array(hits.prefix(normalized.limit)), truncated: truncated)
	}

	@discardableResult
	func saveData() async -> ScrollbackSaveOutcome {
		guard lifecycle == .open else { return .failed(CocoaError(.persistentStoreOperation).localizedDescription) }
		await enter()
		defer { leave() }
		await willPerform?(.save)
		guard let context else { return .failed(CocoaError(.persistentStoreOperation).localizedDescription) }
		return await commit(context)
	}

	/// Saves on the store's own context. Only called holding the store, so no
	/// row can be inserted between the count being cleared and the save.
	private func commit(_ context: NSManagedObjectContext) async -> ScrollbackSaveOutcome {
		rowsSinceSave = 0
		return await context.perform { ScrollbackQueries.quickSave(context) }
	}

	/// Arms the save the rows just written are owed: after `saveDelay` from the
	/// first of them, or now once `saveRowThreshold` of them are waiting.
	private func noteInsertedRow() {
		rowsSinceSave += 1
		if rowsSinceSave >= saveRowThreshold {
			armBurstSave(after: .zero)
		} else if burstSave == nil {
			armBurstSave(after: saveDelay)
		}
	}

	private func armBurstSave(after delay: Duration) {
		guard lifecycle == .open else { return }
		burstSave?.task.cancel()
		let identifier = UUID()
		let task = Task { [weak self] in
			if delay > .zero {
				try? await Task.sleep(for: delay)
			}
			guard !Task.isCancelled else { return }
			await self?.runBurstSave(identifier)
		}
		burstSave = BurstSave(identifier: identifier, task: task)
	}

	private func runBurstSave(_ identifier: UUID) async {
		guard burstSave?.identifier == identifier, lifecycle == .open else { return }
		// Cleared before the save takes its turn, so rows written while it waits arm the next.
		burstSave = nil
		guard case let .failed(reason) = await saveData() else { return }
		await saveFailureHandler(reason)
	}

	private func scheduleSave() {
		guard saveTask == nil else { return }
		let interval = saveInterval
		saveTask = Task { [weak self] in
			while !Task.isCancelled {
				try? await Task.sleep(for: interval)
				guard !Task.isCancelled, let self else { return }
				_ = await saveData()
			}
		}
	}

	private func scheduleResize(_ identifier: String) {
		guard lifecycle == .open, let state = views[identifier], state.resize == nil,
		      state.totalLineCount > maximumLineCount else { return }
		let delay = resizeDelay()
		let requestIdentifier = UUID()
		let task = Task { [weak self] in
			try? await Task.sleep(for: delay)
			guard !Task.isCancelled else { return }
			_ = await self?.resize(identifier, requestIdentifier: requestIdentifier)
		}
		views[identifier]?.resize = ScheduledResize(identifier: requestIdentifier, task: task)
	}

	/// A cancelled pass can finish after a replacement is scheduled for the same view.
	private func releaseResizeSlot(_ identifier: String, requestIdentifier: UUID?) {
		guard requestIdentifier == nil || requestIdentifier == views[identifier]?.resize?.identifier else { return }
		if requestIdentifier == nil {
			views[identifier]?.resize?.task.cancel()
		}
		views[identifier]?.resize = nil
	}

	@discardableResult
	func resize(_ identifier: String, requestIdentifier: UUID? = nil) async -> ScrollbackDeletionOutcome {
		guard lifecycle == .open else { return .unavailable }
		await enter()
		defer { leave() }
		await willPerform?(.resize)
		guard !Task.isCancelled, requestIdentifier == nil || requestIdentifier == views[identifier]?.resize?.identifier,
		      let context
		else {
			releaseResizeSlot(identifier, requestIdentifier: requestIdentifier)
			return .unavailable
		}
		let limit = maximumLineCount
		// A retention pass commits pending rows first, as a removal does.
		rowsSinceSave = 0
		let outcome = await context.perform {
			ScrollbackQueries.deleteOutcome(.retainingNewest(count: limit), in: context, viewIdentifier: identifier)
		}
		releaseResizeSlot(identifier, requestIdentifier: requestIdentifier)
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
