/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 *********************************************************************** */

import CocoaExtensions
import Foundation
import os

private nonisolated let scrollbackClientLogger = Logger( // nonisolated: let
	subsystem: Bundle.main.bundleIdentifier ?? "Glasstual",
	category: "Scrollback"
)

/// Serializes fetches per view while allowing different views to read concurrently.
/// Forgetting a view answers its pending callers with cancellation, not exhaustion.
actor ScrollbackRequestQueue {
	/// The round trip a queued request performs once its turn comes.
	typealias Service = @Sendable (ScrollbackFetchRequest) async -> ScrollbackFetchOutcome

	/// A request waiting for its turn.
	private nonisolated struct QueuedFetch: Sendable { // nonisolated: value
		let identifier: UUID
		let request: ScrollbackFetchRequest
	}

	/// The caller suspended on a request that has not answered yet.
	private nonisolated struct PendingFetch: Sendable { // nonisolated: value
		let viewIdentifier: String
		let continuation: CheckedContinuation<ScrollbackFetchOutcome, Never>
	}

	/// One view's serial stream and the task draining it.
	private nonisolated struct ViewQueue: Sendable { // nonisolated: value
		let continuation: AsyncStream<QueuedFetch>.Continuation
		let pump: Task<Void, Never>

		func close() {
			continuation.finish()
			pump.cancel()
		}
	}

	private let service: Service
	private var queues: [String: ViewQueue] = [:]
	private var pending: [UUID: PendingFetch] = [:]

	init(service: @escaping Service) {
		self.service = service
	}

	/// Queues `request` behind everything already asked for the same view.
	func fetchOutcome(_ request: ScrollbackFetchRequest) async -> ScrollbackFetchOutcome {
		let identifier = UUID()
		let outcome: ScrollbackFetchOutcome = await withTaskCancellationHandler {
			guard !Task.isCancelled else { return .cancelled }
			return await withCheckedContinuation { continuation in
				pending[identifier] = PendingFetch(
					viewIdentifier: request.viewIdentifier,
					continuation: continuation
				)
				viewQueue(for: request.viewIdentifier)
					.yield(QueuedFetch(identifier: identifier, request: request))
			}
		} onCancel: {
			Task { await self.cancelFetch(identifier) }
		}
		return Task.isCancelled ? .cancelled : outcome
	}

	private func cancelFetch(_ identifier: UUID) {
		pending.removeValue(forKey: identifier)?.continuation.resume(returning: .cancelled)
	}

	/// Drops the view's queue and answers everything still waiting on it.
	func forget(view viewIdentifier: String) {
		queues.removeValue(forKey: viewIdentifier)?.close()
		failPending { $0.viewIdentifier == viewIdentifier }
	}

	/// Drops every queue. Used when the connection goes away underneath us.
	func cancelAll() {
		for queue in queues.values {
			queue.close()
		}
		queues.removeAll()
		failPending { _ in true }
	}

	/// How many callers are still suspended. Test seam.
	var pendingCount: Int {
		pending.count
	}

	private func viewQueue(for viewIdentifier: String) -> AsyncStream<QueuedFetch>.Continuation {
		if let existing = queues[viewIdentifier] {
			return existing.continuation
		}

		let (stream, continuation) = AsyncStream<QueuedFetch>.makeStream()
		let pump = Task { [weak self] in
			for await queued in stream {
				guard let self else {
					break
				}
				await serve(queued)
			}
		}

		queues[viewIdentifier] = ViewQueue(continuation: continuation, pump: pump)
		return continuation
	}

	private func serve(_ queued: QueuedFetch) async {
		/* The view can be forgotten between queueing and serving; the caller has
		 already been answered in that case, so there is nothing left to fetch. */
		guard pending[queued.identifier] != nil else {
			return
		}

		let outcome = await service(queued.request)
		pending.removeValue(forKey: queued.identifier)?.continuation.resume(returning: outcome)
	}

	private func failPending(_ isMatch: (PendingFetch) -> Bool) {
		let identifiers = pending.filter { isMatch($0.value) }.map(\.key)

		for identifier in identifiers {
			cancelFetch(identifier)
		}
	}
}

/** The storage operations the client drives.

 Closures rather than a protocol: `ScrollbackStore` is the only thing that
 implements them, and a test that wants an open to fail supplies its own
 closures instead of a second conformer, so opening failures never touch the
 reader's database. */
nonisolated struct ScrollbackStorage: Sendable { // nonisolated: value
	var openDatabase: @Sendable (String) async -> ScrollbackOpenOutcome
	var close: @Sendable () async -> ScrollbackSaveOutcome
	var setMaximumLineCount: @Sendable (UInt) async -> Void
	var writeLogLine: @Sendable (ScrollbackEntry) async -> ScrollbackWriteOutcome
	var forgetView: @Sendable (String) async -> ScrollbackDeletionOutcome
	var resetData: @Sendable (String) async -> ScrollbackDeletionOutcome
	var saveData: @Sendable () async -> ScrollbackSaveOutcome
	var fetchOutcome: @Sendable (ScrollbackFetchRequest) async -> ScrollbackFetchOutcome

	/// The real database.
	static func store(_ store: ScrollbackStore) -> Self {
		Self(
			openDatabase: { await store.openDatabase(inDirectory: $0) },
			close: { await store.close() },
			setMaximumLineCount: { await store.setMaximumLineCount($0) },
			writeLogLine: { await store.writeLogLine($0) },
			forgetView: { await store.forgetView($0) },
			resetData: { await store.resetData(forView: $0) },
			saveData: { await store.saveData() },
			fetchOutcome: { await store.fetchOutcome($0) }
		)
	}
}

/// Coordinates the in-process history store and preserves FIFO fetch ordering
/// per view. Core Data and save scheduling remain isolated by `ScrollbackStore`.
actor ScrollbackClient {
	static let shared = ScrollbackClient()

	/** Where the database stands for this process.

	 Shutting down is an axis of its own rather than a case here: the close a
	 termination performs can fail, and the caller is then free to retry it, so
	 whatever the database was before has to survive the attempt. */
	private nonisolated enum LoadState { // nonisolated: value
		case unloaded
		case loading(Task<Bool, Never>)
		case loaded
		case unavailable
	}

	private let databaseDirectory: @Sendable () async -> String?
	private let store: ScrollbackStorage
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

	private lazy var requests = ScrollbackRequestQueue { [weak self] request in
		await self?.store.fetchOutcome(request) ?? .cancelled
	}

	init(
		databaseDirectory: String? = ApplicationPaths.groupContainerApplicationCaches,
		filenameStore: ScrollbackFilenameStore = .preferences
	) {
		self.databaseDirectory = { databaseDirectory }
		reportFailure = { Scrollback.reportConnectionFailure($0) }
		store = .store(ScrollbackStore(filenameStore: filenameStore, deletionHandler: { identifiers, viewIdentifier in
			await Scrollback.noteWillDeleteLines(identifiers, inView: viewIdentifier)
		}))
	}

	init(
		store: ScrollbackStorage,
		databaseDirectory: @escaping @Sendable () async -> String?,
		reportFailure: @escaping @MainActor @Sendable (String) -> Void
	) {
		self.store = store
		self.databaseDirectory = databaseDirectory
		self.reportFailure = reportFailure
	}

	// MARK: - Decoding

	nonisolated static func logLines(from historicEntries: [ScrollbackEntry]) -> [LogLine] { // nonisolated: pure
		historicEntries.compactMap { historicEntry in
			guard let logLine = LogLine.logLine(from: historicEntry) else {
				scrollbackClientLogger.error(
					"Failed to decode historic line \(historicEntry.uniqueIdentifier, privacy: .public)"
				)
				return nil
			}
			return logLine
		}
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
		let outcome = await store.openDatabase(databaseDirectory)
		guard isTerminating == false else { return false }

		switch outcome {
		case .opened:
			loadState = .loaded
			scrollbackClientLogger.debug("Successfully opened historic log database")
			await applyMaximumLineCount()
		case let .failed(reason):
			// Latch before presenting the alert, which can suspend this actor.
			loadState = .unavailable
			scrollbackClientLogger
				.error("Failed to open historic log database: \(reason ?? "no reason given", privacy: .public)")
			/* The alert is the only place the failure reaches the reader, so it
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
		await store.setMaximumLineCount(Preferences.Logging.scrollbackSaveLimit.detachedValue)
	}

	// MARK: - Fetching

	func fetchOutcome(_ request: ScrollbackFetchRequest) async -> ScrollbackFetchOutcome {
		guard !isTerminating, !Task.isCancelled else { return .cancelled }
		guard await ensureLoaded()
		else { return isTerminating || Task.isCancelled ? .cancelled : .failed(.unavailable) }
		guard !isTerminating, !Task.isCancelled else { return .cancelled }
		let outcome = await requests.fetchOutcome(request)
		return isTerminating || Task.isCancelled ? .cancelled : outcome
	}

	// MARK: - Writing

	@discardableResult
	func writeEntry(_ entry: ScrollbackEntry) async -> ScrollbackWriteOutcome {
		guard await ensureLoaded(), !isTerminating else { return .unavailable }
		return await store.writeLogLine(entry)
	}

	@discardableResult
	func removeHistory(_ viewIdentifier: String, forget: Bool) async -> ScrollbackDeletionOutcome {
		await requests.forget(view: viewIdentifier)
		guard await ensureLoaded(), !isTerminating else { return .unavailable }
		return forget
			? await store.forgetView(viewIdentifier)
			: await store.resetData(viewIdentifier)
	}

	func saveData() async -> ScrollbackSaveOutcome {
		await store.saveData()
	}

	// MARK: - Termination

	@discardableResult
	func prepareForTermination() async -> ScrollbackSaveOutcome {
		isTerminating = true
		await requests.cancelAll()
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
