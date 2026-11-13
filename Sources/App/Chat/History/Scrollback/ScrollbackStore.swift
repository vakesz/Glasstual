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

	private var lifecycle = Lifecycle.closed
	private var turns = ScrollbackTurnQueue()
	private var closingCount = 0
	private var context: NSManagedObjectContext?
	private var databaseURL: URL?
	private var views = ScrollbackViewCounts()
	private var saveTask: Task<Void, Never>?
	private var saves: ScrollbackSaveSchedule
	private let filenameSetting: ScrollbackFilenameSetting
	private let deletionHandler: DeletionHandler
	private let saveFailureHandler: SaveFailureHandler
	private let makeStack: MakeStack
	private let resizeDelay: ResizeDelay
	/** The most rows one step of a removal or a retention pass deletes and
	 saves before queued work gets its turn. A thousand rows is about 1.4 MB of
	 registered objects. */
	private let deletionChunkSize: Int
	private let willPerform: (@Sendable (ScrollbackStoreOperation) async -> Void)?
	var pendingOperationCount: Int {
		turns.pendingCount
	}

	init(
		filenameSetting: ScrollbackFilenameSetting,
		makeStack: MakeStack? = nil,
		migrationProgress: @escaping @Sendable (Double) -> Void = { _ in },
		resizeDelay: @escaping ResizeDelay = { .seconds(Int.random(in: 0 ..< 1800)) },
		saveInterval: Duration = .seconds(120),
		saveRowThreshold: Int = 500,
		saveDelay: Duration = .seconds(5),
		deletionChunkSize: Int = 1000,
		willPerform: (@Sendable (ScrollbackStoreOperation) async -> Void)? = nil,
		saveFailureHandler: @escaping SaveFailureHandler = { _ in },
		deletionHandler: @escaping DeletionHandler = { _, _ in }
	) {
		self.filenameSetting = filenameSetting
		self.makeStack = makeStack ?? { try ScrollbackQueries.makeStack(at: $0, migrationProgress: migrationProgress) }
		self.resizeDelay = resizeDelay
		saves = ScrollbackSaveSchedule(saveInterval: saveInterval, saveRowThreshold: saveRowThreshold, saveDelay: saveDelay)
		self.deletionChunkSize = max(1, deletionChunkSize)
		self.willPerform = willPerform
		self.saveFailureHandler = saveFailureHandler
		self.deletionHandler = deletionHandler
	}

	private func enter() async {
		if !turns.claim() {
			await withCheckedContinuation { turns.enqueue($0) }
		}
	}

	private func leave() {
		turns.handOff()?.resume()
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
		saves.cancel()
		await enter()
		defer { closingCount -= 1; leave() }
		await willPerform?(.close)
		views.cancelAllResizes()
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
			views.forgetResizes()
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
		for identifier in views.setMaximumLineCount(count) {
			scheduleResize(identifier)
		}
	}

	private func initializeView(_ identifier: String, in context: NSManagedObjectContext) async throws {
		guard views.contains(identifier) == false else { return }
		let counts = try await context.perform {
			try ScrollbackQueries.initialCounts(in: context, viewIdentifier: identifier)
		}
		views.insert(identifier, lineCount: counts.lineCount, maximumIdentifier: counts.maximumIdentifier)
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
			guard let maximumIdentifier = views.maximumIdentifier(of: entry.viewIdentifier),
			      maximumIdentifier < UInt(Int64.max)
			else {
				return .failed(CocoaError(.validationNumberTooLarge).localizedDescription)
			}
			let next = maximumIdentifier + 1
			let inserted = await context
				.perform { ScrollbackQueries.insert(entry, in: context, entryIdentifier: next) }
			guard inserted else { return .failed(CocoaError(.persistentStoreOperation).localizedDescription) }
			views.noteInserted(entry.viewIdentifier, entryIdentifier: next)
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
		/* The rows to remove are the ones written before the removal was asked
		 for. A line queued behind it may be written between two chunks, gets a
		 higher entry identifier, and stays. */
		let ceiling: UInt
		do {
			ceiling = try await context.perform {
				try ScrollbackQueries.initialCounts(in: context, viewIdentifier: identifier).maximumIdentifier
			}
		} catch { return .failed(error.localizedDescription) }
		let outcome = await deleteInChunks(
			.everything(throughEntryIdentifier: max(ceiling, views.maximumIdentifier(of: identifier) ?? 0)),
			inView: identifier, context: context, continues: { true }
		)
		if case .deleted = outcome {
			if forget {
				views.removeView(identifier)
			} else {
				views.cancelResize(identifier)
			}
		}
		return outcome
	}

	/** Runs `deletion` a chunk at a time, holding the store for each chunk and
	 letting the work queued behind it run in between.

	 Each chunk takes its rows off the view's count and reports the identifiers
	 it removed before the store is let go, so the duplicate index never trails
	 the database. A failure stops the run: the chunks before it stay deleted
	 and were reported, and the failure is what the run answers. `continues` is
	 asked before every later chunk; a run it stops answers what it deleted. */
	private func deleteInChunks(
		_ deletion: ScrollbackQueries.Deletion,
		inView identifier: String,
		context: NSManagedObjectContext,
		continues: () -> Bool
	) async -> ScrollbackDeletionOutcome {
		let chunkLimit = deletionChunkSize
		var deletedCount: UInt = 0
		var uniqueIdentifiers: [String] = []
		while true {
			// A deletion saves what is pending before it deletes, and again after.
			saves.noteSaveAttempt()
			let outcome = await context.perform {
				ScrollbackQueries.deleteOutcome(
					deletion, in: context, viewIdentifier: identifier, chunkLimit: chunkLimit
				)
			}
			guard case let .deleted(chunk) = outcome else { return outcome }
			deletedCount = saturatedAdd(deletedCount, chunk.deletedCount)
			uniqueIdentifiers += chunk.uniqueIdentifiers
			views.subtract(chunk.deletedCount, from: identifier)
			// The one-way notification completes before a newer view generation can enter.
			if !chunk.uniqueIdentifiers.isEmpty {
				await deletionHandler(chunk.uniqueIdentifiers, identifier)
			}
			guard chunk.hasMore else { break }
			await yieldBetweenChunks()
			guard self.context === context else { return .unavailable }
			guard continues() else { break }
		}
		return .deleted(ScrollbackQueries.DeletionResult(deletedCount: deletedCount, uniqueIdentifiers: uniqueIdentifiers))
	}

	/** Hands the store to the operations queued behind a long deletion, and
	 takes it back after them.

	 Not while a close is waiting: it would end the deletion halfway, and a
	 removal that was accepted finishes before the store closes, as it did when
	 it was one transaction. */
	private func yieldBetweenChunks() async {
		guard closingCount == 0, pendingOperationCount > 0 else { return }
		leave()
		await enter()
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
			case let .messageWindow(messageIdentifier, olderLimit, newerLimit):
				ScrollbackQueries.fetchWindow(in: context, viewIdentifier: request.viewIdentifier,
				                              aroundMessageIdentifier: messageIdentifier,
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

		guard let reader = await ScrollbackQueries.makeReader(for: context) else { return .unavailable }
		return await ScrollbackQueries.search(query.normalized, reader: reader)
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
		saves.noteSaveAttempt()
		return await context.perform { ScrollbackQueries.quickSave(context) }
	}

	/// Arms the save the rows just written are owed: after `saveDelay` from the
	/// first of them, or now once `saveRowThreshold` of them are waiting.
	private func noteInsertedRow() {
		if let delay = saves.noteInsertedRow() {
			armBurstSave(after: delay)
		}
	}

	private func armBurstSave(after delay: Duration) {
		guard lifecycle == .open else { return }
		saves.burstSave?.task.cancel()
		let identifier = UUID()
		let task = Task { [weak self] in
			if delay > .zero {
				try? await Task.sleep(for: delay)
			}
			guard !Task.isCancelled else { return }
			await self?.runBurstSave(identifier)
		}
		saves.arm(ScrollbackSaveSchedule.BurstSave(identifier: identifier, task: task))
	}

	private func runBurstSave(_ identifier: UUID) async {
		// Cleared before the save takes its turn, so rows written while it waits arm the next.
		guard lifecycle == .open, saves.takeBurst(identifier), case let .failed(reason) = await saveData() else { return }
		await saveFailureHandler(reason)
	}

	private func scheduleSave() {
		guard saveTask == nil else { return }
		let interval = saves.saveInterval
		saveTask = Task { [weak self] in
			while !Task.isCancelled {
				try? await Task.sleep(for: interval)
				guard !Task.isCancelled, let self else { return }
				_ = await saveData()
			}
		}
	}

	private func scheduleResize(_ identifier: String) {
		guard lifecycle == .open, views.needsResize(identifier) else { return }
		let delay = resizeDelay()
		let requestIdentifier = UUID()
		let task = Task { [weak self] in
			try? await Task.sleep(for: delay)
			guard !Task.isCancelled else { return }
			_ = await self?.resize(identifier, requestIdentifier: requestIdentifier)
		}
		views.armResize(identifier, ScrollbackViewCounts.ScheduledResize(identifier: requestIdentifier, task: task))
	}

	@discardableResult
	func resize(_ identifier: String, requestIdentifier: UUID? = nil) async -> ScrollbackDeletionOutcome {
		guard lifecycle == .open else { return .unavailable }
		await enter()
		defer { leave() }
		await willPerform?(.resize)
		guard !Task.isCancelled, views.isCurrent(requestIdentifier, for: identifier), let context else {
			views.releaseResizeSlot(identifier, requestIdentifier: requestIdentifier)
			return .unavailable
		}
		/* A retention pass commits pending rows first, as a removal does. A pass
		 that was cancelled, replaced or given another limit between its chunks
		 stops there; the limit's own pass takes over. */
		let limit = views.maximumLineCount
		let outcome = await deleteInChunks(
			.retainingNewest(count: limit), inView: identifier, context: context,
			continues: {
				!Task.isCancelled && views.maximumLineCount == limit && views.isCurrent(requestIdentifier, for: identifier)
			}
		)
		views.releaseResizeSlot(identifier, requestIdentifier: requestIdentifier)
		if case let .deleted(result) = outcome, result.deletedCount > 0 {
			/* One pass may leave the view over its limit — the limit can have been
			 lowered again while this one ran. A pass that deleted nothing arms no
			 successor, so a counter that disagrees with the store cannot spin. */
			scheduleResize(identifier)
		}
		return outcome
	}
}
