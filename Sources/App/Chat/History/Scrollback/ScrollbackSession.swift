// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation
import os

private nonisolated let scrollbackSessionLogger = Logger(
	subsystem: LogSubsystem.current,
	category: "ScrollbackSession"
)

/** Coordinates the in-process history store and runs what is asked of it in the
 order it was asked.

 The one ordering point in the scrollback: a line has to be stored before a
 later clear of the same view drops it, and a page has to see the lines queued
 ahead of it, so every change goes through ``changes`` and every fetch waits for
 what was asked before it. Below this, ``ScrollbackStore`` owns the Core Data
 transaction and nothing else. */
actor ScrollbackSession {
	static let shared = ScrollbackSession()

	/// One change to stored history, run in its turn.
	private typealias Change = @Sendable () async -> Void

	/** Where the database stands for this process.

	 Shutting down is an axis of its own rather than a case here: the close a
	 termination performs can fail, and the caller is then free to retry it, so
	 whatever the database was before has to survive the attempt. */
	private nonisolated enum LoadState {
		case unloaded
		case loading(Task<Bool, Never>)
		case loaded
		case unavailable
	}

	/** The changes asked for, in that order.

	 A `nonisolated let` continuation because `yield` is synchronous: the order the
	 caller asks in is the order the pump runs them in, which entering this actor
	 would not preserve — the order suspended callers resume in is unspecified. One
	 queue rather than one per view, because the store runs one transaction at a
	 time and a second queue would only move the wait. */
	private nonisolated let changes: AsyncStream<Change>.Continuation
	private let databaseDirectory: @Sendable () async -> String?
	private let store: ScrollbackStore
	/** Where a database that will not open is reported.

	 Storage presents nothing itself: the in-transcript recovery banner already
	 draws every other storage failure and is the only place the retry is
	 offered, so an open failure is recorded there too. */
	private let reportFailure: @MainActor @Sendable (String) -> Void
	private var loadState = LoadState.unloaded
	private var isTerminating = false

	var isLoaded: Bool {
		if case .loaded = loadState {
			true
		} else {
			false
		}
	}

	var isUnavailable: Bool {
		if case .unavailable = loadState {
			true
		} else {
			false
		}
	}

	init(
		databaseDirectory: String? = ApplicationPaths.groupContainerApplicationCaches,
		filenameSetting: ScrollbackFilenameSetting = .stored
	) {
		self.init(
			store: ScrollbackStore(
				filenameSetting: filenameSetting,
				deletionHandler: { identifiers, viewIdentifier in
					await Scrollback.noteWillDeleteLines(identifiers, inView: viewIdentifier)
				}
			),
			databaseDirectory: { databaseDirectory },
			reportFailure: { Scrollback.shared.recovery.storageFailure = $0 }
		)
	}

	init(
		store: ScrollbackStore,
		databaseDirectory: @escaping @Sendable () async -> String?,
		reportFailure: @escaping @MainActor @Sendable (String) -> Void
	) {
		self.store = store
		self.databaseDirectory = databaseDirectory
		self.reportFailure = reportFailure
		let (queued, continuation) = AsyncStream<Change>.makeStream()
		changes = continuation
		/* The pump holds the queue and not the session, so a session nobody else
		 holds still deinitializes; what is queued holds it until it has run. */
		Task {
			for await change in queued {
				await change()
			}
		}
	}

	deinit {
		changes.finish()
	}

	// MARK: - Decoding

	/** The lines a stored page holds, and whether every row in it decoded.

	 Both readers of a page answer a shortfall the same way — the page they were
	 handed is not the page they asked for, so it is reported as
	 ``ScrollbackFetchFailure/invalidEntry`` — and the rows that did decode are
	 still worth drawing. Stating both here is what keeps the rule from being
	 counted out again at each call site. */
	nonisolated static func decode( // nonisolated: pure
		_ storedEntries: [ScrollbackEntry]
	) -> (lines: [ChatLine], isWholePage: Bool) {
		let lines: [ChatLine] = storedEntries.compactMap { scrollbackEntry in
			guard let chatLine = ChatLine(entry: scrollbackEntry) else {
				scrollbackSessionLogger.error(
					"Failed to decode a stored line \(scrollbackEntry.uniqueIdentifier, privacy: .public)"
				)
				return nil
			}
			return chatLine
		}
		return (lines, lines.count == storedEntries.count)
	}

	// MARK: - Lifecycle

	@discardableResult
	private func ensureLoaded() async -> Bool {
		guard isTerminating == false else {
			return false
		}
		switch loadState {
		case .loaded:
			return true
		case .unavailable:
			return false
		case let .loading(task):
			return await task.value && isTerminating == false
		case .unloaded:
			let task = Task { await self.loadDatabase() }
			loadState = .loading(task)
			return await task.value && isTerminating == false
		}
	}

	private func loadDatabase() async -> Bool {
		guard let databaseDirectory = await databaseDirectory() else {
			// Setup has not supplied a directory yet; no database open has failed.
			loadState = .unloaded
			return false
		}
		guard isTerminating == false else { return false }
		let outcome = await store.openDatabase(inDirectory: databaseDirectory)
		guard isTerminating == false else { return false }

		switch outcome {
		case .opened:
			loadState = .loaded
			scrollbackSessionLogger.debug("Successfully opened the scrollback database")
			await applyMaximumLineCount()
		case let .failed(reason):
			// Latch before the hop to the main actor, which suspends this actor.
			loadState = .unavailable
			scrollbackSessionLogger
				.error("Failed to open the scrollback database: \(reason ?? "no reason given", privacy: .public)")
			/* The banner is the only place the failure reaches the reader, so it
			 carries what the store knows rather than an empty body. */
			await reportFailure(
				reason.map(PromptStrings.Logging.lastError) ?? PromptStrings.Logging.scrollbackFailureBody
			)
		}

		return outcome.isOpen
	}

	/// Retries the selected database after recovery, without replacing its file.
	/// Ordinary writes and fetches never clear an actual open failure.
	@discardableResult
	func retryLoading() async -> Bool {
		guard isTerminating == false else { return false }
		if isUnavailable {
			loadState = .unloaded
		}
		return await ensureLoaded()
	}

	func applyMaximumLineCount() async {
		await store.setMaximumLineCount(SettingsKeys.Logging.scrollbackSaveLimit.detachedValue)
	}

	// MARK: - The order changes are asked in

	/** Queues an archived line for storage, behind the changes already asked for.

	 Nonisolated so that asking costs the caller nothing: the caller is the main
	 actor printing a line, and the order it prints in is the order the lines are
	 stored in. `completion` reports what the store answered, on the main actor. */
	nonisolated func write( // nonisolated: pure
		_ entry: ScrollbackEntry,
		completion: @escaping @MainActor @Sendable (ScrollbackWriteOutcome) -> Void
	) {
		changes.yield { [self] in
			let outcome = await writeEntry(entry)
			await completion(outcome)
		}
	}

	/// Queues a view's removal behind the writes already asked for it, and reports
	/// whether the queue took it.
	nonisolated func removeHistory( // nonisolated: pure
		forView viewIdentifier: String,
		forget: Bool,
		completion: @escaping @MainActor @Sendable (ScrollbackDeletionOutcome) -> Void
	) -> Bool {
		queue { [self] in
			let outcome = await removeHistory(viewIdentifier, forget: forget)
			await completion(outcome)
		}
	}

	/// Returns once every change asked for before now has run.
	nonisolated func drain() async { // nonisolated: pure
		await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
			if queue({ continuation.resume() }) == false {
				continuation.resume()
			}
		}
	}

	@discardableResult
	private nonisolated func queue(_ change: @escaping Change) -> Bool { // nonisolated: pure
		if case .terminated = changes.yield(change) {
			return false
		}
		return true
	}

	// MARK: - Fetching

	func fetchOutcome(_ request: ScrollbackFetchRequest) async -> ScrollbackFetchOutcome {
		guard !isTerminating, !Task.isCancelled else { return .cancelled }
		guard await ensureLoaded()
		else { return isTerminating || Task.isCancelled ? .cancelled : .failed(.unavailable) }
		/* The page has to hold the lines asked for before it, so the fetch takes
		 its turn behind them rather than racing the store for admission. */
		await drain()
		guard !isTerminating, !Task.isCancelled else { return .cancelled }
		let outcome = await store.fetchOutcome(request)
		return isTerminating || Task.isCancelled ? .cancelled : outcome
	}

	// MARK: - Writing

	/// Stores the line now, rather than in the order it was asked for; the caller
	/// that has to see the outcome in its own turn awaits this, and the printing
	/// path queues instead.
	@discardableResult
	func writeEntry(_ entry: ScrollbackEntry) async -> ScrollbackWriteOutcome {
		guard await ensureLoaded(), !isTerminating else { return .unavailable }
		return await store.writeChatLine(entry)
	}

	@discardableResult
	func removeHistory(_ viewIdentifier: String, forget: Bool) async -> ScrollbackDeletionOutcome {
		guard await ensureLoaded(), !isTerminating else { return .unavailable }
		return forget
			? await store.forgetView(viewIdentifier)
			: await store.resetData(forView: viewIdentifier)
	}

	func saveData() async -> ScrollbackSaveOutcome {
		await store.saveData()
	}

	// MARK: - Termination

	@discardableResult
	func prepareForTermination() async -> ScrollbackSaveOutcome {
		isTerminating = true
		if case let .loading(task) = loadState {
			_ = await task.value
		}
		let result = await store.close()
		/* A close that failed leaves the database where it was, so the caller
		 can retry it. */
		if case .saved = result {
			loadState = .unloaded
		} else {
			isTerminating = false
		}
		return result
	}
}
