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

private nonisolated let historicLogClientLogger = Logger( // nonisolated: let
	subsystem: Bundle.main.bundleIdentifier ?? "Glasstual",
	category: "HistoricLogClient"
)

/// Serializes fetches per view while allowing different views to read concurrently.
/// Forgetting a view answers its pending callers with cancellation, not exhaustion.
actor HistoricLogRequestQueue {
	/// The round trip a queued request performs once its turn comes.
	typealias Service = @Sendable (HistoricLogFetchRequest) async -> HistoricLogFetchOutcome

	/// A request waiting for its turn.
	private nonisolated struct QueuedFetch: Sendable { // nonisolated: value
		let identifier: UUID
		let request: HistoricLogFetchRequest
	}

	/// The caller suspended on a request that has not answered yet.
	private nonisolated struct PendingFetch: Sendable { // nonisolated: value
		let viewIdentifier: String
		let continuation: CheckedContinuation<HistoricLogFetchOutcome, Never>
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
	func fetch(_ request: HistoricLogFetchRequest) async -> [HistoricLogEntry] {
		await fetchOutcome(request).entries
	}

	func fetchOutcome(_ request: HistoricLogFetchRequest) async -> HistoricLogFetchOutcome {
		let identifier = UUID()
		let outcome: HistoricLogFetchOutcome = await withTaskCancellationHandler {
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

/// The typed preference that remembers the existing on-disk database name.
private nonisolated struct HistoricLogDefaultsFilenameStore: HistoricLogFilenameStoring { // nonisolated: value
	var databaseFilename: String? {
		get {
			let value = TextualUserDefaults.suite().string(forKey: Preferences.Logging.historicLogFileName.name)
			return value?.isEmpty == false ? value : nil
		}
		nonmutating set {
			TextualUserDefaults.suite().set(newValue, forKey: Preferences.Logging.historicLogFileName.name)
		}
	}
}

/// The actor-owned storage operations used by the client. Tests supply an
/// in-memory service so opening failures never touch the user's database.
protocol HistoricLogServicing: Actor {
	func openDatabase(inDirectory databaseDirectory: String) async -> HistoricLogOpenOutcome
	func close() async -> HistoricLogSaveOutcome
	func setMaximumLineCount(_ maximumLineCount: UInt) async
	func writeLogLine(_ logLine: HistoricLogEntry) async -> HistoricLogWriteOutcome
	func forgetView(_ viewIdentifier: String) async -> HistoricLogDeletionOutcome
	func resetData(forView viewIdentifier: String) async -> HistoricLogDeletionOutcome
	func saveData() async -> HistoricLogSaveOutcome
	func fetchOutcome(_ request: HistoricLogFetchRequest) async -> HistoricLogFetchOutcome
}

extension HistoricLogStore: HistoricLogServicing {}

/// Coordinates the in-process history store and preserves FIFO fetch ordering
/// per view. Core Data and save scheduling remain isolated by `HistoricLogStore`.
actor HistoricLogClient {
	static let shared = HistoricLogClient()

	private nonisolated enum LoadState { // nonisolated: value
		case unloaded
		case loading(Task<Bool, Never>)
		case loaded
		case unavailable
	}

	private let databaseDirectory: @Sendable () async -> String?
	private let store: any HistoricLogServicing
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

	private lazy var requests = HistoricLogRequestQueue { [weak self] request in
		await self?.store.fetchOutcome(request) ?? .cancelled
	}

	init(
		databaseDirectory: String? = PathInfo.groupContainerApplicationCaches,
		filenameStore: any HistoricLogFilenameStoring = HistoricLogDefaultsFilenameStore()
	) {
		self.databaseDirectory = { databaseDirectory }
		reportFailure = { LogControllerHistoricLogFile.reportConnectionFailure($0) }
		store = HistoricLogStore(filenameStore: filenameStore, deletionHandler: { identifiers, viewIdentifier in
			await LogControllerHistoricLogFile.noteWillDeleteLines(identifiers, inView: viewIdentifier)
		})
	}

	init(
		store: any HistoricLogServicing,
		databaseDirectory: @escaping @Sendable () async -> String?,
		reportFailure: @escaping @MainActor @Sendable (String) -> Void
	) {
		self.store = store
		self.databaseDirectory = databaseDirectory
		self.reportFailure = reportFailure
	}

	// MARK: - Decoding

	nonisolated static func logLines(from historicEntries: [HistoricLogEntry]) -> [LogLine] { // nonisolated: pure
		historicEntries.compactMap { historicEntry in
			guard let logLine = LogLine.logLine(from: historicEntry) else {
				historicLogClientLogger.error(
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
		let outcome = await store.openDatabase(inDirectory: databaseDirectory)
		guard isTerminating == false else { return false }

		switch outcome {
		case .opened:
			loadState = .loaded
			historicLogClientLogger.debug("Successfully opened historic log database")
			await applyMaximumLineCount()
		case let .failed(reason):
			// Latch before presenting the alert, which can suspend this actor.
			loadState = .unavailable
			historicLogClientLogger
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

	func fetchEntries(_ request: HistoricLogFetchRequest) async -> [HistoricLogEntry] {
		await fetchOutcome(request).entries
	}

	func fetchOutcome(_ request: HistoricLogFetchRequest) async -> HistoricLogFetchOutcome {
		guard !isTerminating, !Task.isCancelled else { return .cancelled }
		guard await ensureLoaded()
		else { return isTerminating || Task.isCancelled ? .cancelled : .failed(.unavailable) }
		guard !isTerminating, !Task.isCancelled else { return .cancelled }
		let outcome = await requests.fetchOutcome(request)
		return isTerminating || Task.isCancelled ? .cancelled : outcome
	}

	// MARK: - Writing

	@discardableResult
	func writeEntry(_ entry: HistoricLogEntry) async -> HistoricLogWriteOutcome {
		guard await ensureLoaded(), !isTerminating else { return .unavailable }
		return await store.writeLogLine(entry)
	}

	@discardableResult
	func forgetView(_ viewIdentifier: String) async -> HistoricLogDeletionOutcome {
		await requests.forget(view: viewIdentifier)
		guard await ensureLoaded(), !isTerminating else { return .unavailable }
		return await store.forgetView(viewIdentifier)
	}

	@discardableResult
	func resetData(forView viewIdentifier: String) async -> HistoricLogDeletionOutcome {
		await requests.forget(view: viewIdentifier)
		guard await ensureLoaded(), !isTerminating else { return .unavailable }
		return await store.resetData(forView: viewIdentifier)
	}

	func saveData() async -> HistoricLogSaveOutcome {
		await store.saveData()
	}

	// MARK: - Termination

	@discardableResult
	func prepareForTermination() async -> HistoricLogSaveOutcome {
		isTerminating = true
		await requests.cancelAll()
		if case let .loading(task) = loadState {
			_ = await task.value
		}
		let result = await store.close()
		if case .saved = result {
			loadState = .unloaded
		} else {
			isTerminating = false
		}
		return result
	}
}
