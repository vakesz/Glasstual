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

/// One historic-log fetch, in the shape the store understands. A value, so a
/// request can be queued and replayed without carrying anything isolated.
nonisolated struct HistoricLogFetchRequest: Sendable { // nonisolated: value
	/// Which of the store's fetches to run: the newest page of a view, or the
	/// page before a line the view already holds.
	enum Kind: Sendable {
		case newest(ascending: Bool, fetchLimit: UInt, limitToDate: Date?)
		case before(uniqueIdentifier: String, fetchLimit: UInt, limitToDate: Date?)
	}

	let viewIdentifier: String
	let kind: Kind
}

/** Serialises fetches per view.

 The printing queue used to provide this ordering by holding a slot open for the
 whole round trip. It is this queue's job now: requests for one view are served
 one at a time in the order they were made, requests for different views run
 concurrently, and forgetting a view answers everything still queued for it with
 the empty result rather than leaving a caller suspended forever. */
actor HistoricLogRequestQueue {
	/// The round trip a queued request performs once its turn comes.
	typealias Service = @Sendable (HistoricLogFetchRequest) async -> [HistoricLogEntry]

	/// A request waiting for its turn.
	private nonisolated struct QueuedFetch: Sendable { // nonisolated: value
		let identifier: UUID
		let request: HistoricLogFetchRequest
	}

	/// The caller suspended on a request that has not answered yet.
	private nonisolated struct PendingFetch: Sendable { // nonisolated: value
		let viewIdentifier: String
		let continuation: CheckedContinuation<[HistoricLogEntry], Never>
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
		let identifier = UUID()

		return await withCheckedContinuation { continuation in
			pending[identifier] = PendingFetch(
				viewIdentifier: request.viewIdentifier,
				continuation: continuation
			)
			viewQueue(for: request.viewIdentifier)
				.yield(QueuedFetch(identifier: identifier, request: request))
		}
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

		let entries = await service(queued.request)
		pending.removeValue(forKey: queued.identifier)?.continuation.resume(returning: entries)
	}

	private func failPending(_ isMatch: (PendingFetch) -> Bool) {
		let identifiers = pending.filter { isMatch($0.value) }.map(\.key)

		for identifier in identifiers {
			pending.removeValue(forKey: identifier)?.continuation.resume(returning: [])
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

/// Coordinates the in-process history store and preserves FIFO fetch ordering
/// per view. Core Data and save scheduling remain isolated by `HistoricLogStore`.
actor HistoricLogClient {
	static let shared = HistoricLogClient()

	private let databaseDirectory: String?
	private let store: HistoricLogStore
	private var loadTask: Task<HistoricLogOpenOutcome, Never>?
	private(set) var isLoaded = false
	private var isTerminating = false

	private lazy var requests = HistoricLogRequestQueue { [weak self] request in
		await self?.performFetch(request) ?? []
	}

	init(
		databaseDirectory: String? = PathInfo.groupContainerApplicationCaches,
		filenameStore: any HistoricLogFilenameStoring = HistoricLogDefaultsFilenameStore()
	) {
		self.databaseDirectory = databaseDirectory
		store = HistoricLogStore(filenameStore: filenameStore) { identifiers, viewIdentifier in
			await LogControllerHistoricLogFile.noteWillDeleteLines(identifiers, inView: viewIdentifier)
		}
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
		if isLoaded {
			return true
		}
		if let loadTask {
			let opened = await loadTask.value.isOpen
			return isTerminating == false && opened
		}
		guard let databaseDirectory else {
			return false
		}

		let task = Task { [store] in
			await store.openDatabase(inDirectory: databaseDirectory)
		}
		loadTask = task
		let outcome = await task.value
		loadTask = nil
		guard isTerminating == false else {
			if case .opened = outcome {
				await store.close()
			}
			return false
		}
		isLoaded = outcome.isOpen

		switch outcome {
		case .opened:
			historicLogClientLogger.debug("Successfully opened historic log database")
			await applyMaximumLineCount()
		case let .failed(reason):
			historicLogClientLogger
				.error("Failed to open historic log database: \(reason ?? "no reason given", privacy: .public)")
			/* The alert is the only place the failure reaches the reader, so it
			 carries what the store knows rather than an empty body. */
			await LogControllerHistoricLogFile.reportConnectionFailure(
				reason.map(PromptStrings.Logging.lastError) ?? PromptStrings.Logging.scrollbackFailureBody
			)
		}

		return outcome.isOpen
	}

	func applyMaximumLineCount() async {
		await store.setMaximumLineCount(Preferences.Logging.scrollbackSaveLimit.detachedValue)
	}

	// MARK: - Fetching

	func fetchEntries(_ request: HistoricLogFetchRequest) async -> [HistoricLogEntry] {
		guard await ensureLoaded() else { return [] }
		return await requests.fetch(request)
	}

	private func performFetch(_ request: HistoricLogFetchRequest) async -> [HistoricLogEntry] {
		let viewIdentifier = request.viewIdentifier

		switch request.kind {
		case let .newest(ascending, fetchLimit, limitToDate):
			return await store.fetchEntries(
				forView: viewIdentifier,
				ascending: ascending,
				fetchLimit: fetchLimit,
				limitToDate: limitToDate
			)
		case let .before(uniqueIdentifier, fetchLimit, limitToDate):
			return await store.fetchEntries(
				forView: viewIdentifier,
				before: uniqueIdentifier,
				fetchLimit: fetchLimit,
				limitToDate: limitToDate
			)
		}
	}

	// MARK: - Writing

	func writeEntry(_ entry: HistoricLogEntry) async {
		guard await ensureLoaded() else { return }
		await store.writeLogLine(entry)
	}

	func forgetView(_ viewIdentifier: String) async {
		await requests.forget(view: viewIdentifier)
		guard await ensureLoaded() else { return }
		await store.forgetView(viewIdentifier)
	}

	func resetData(forView viewIdentifier: String) async {
		await requests.forget(view: viewIdentifier)
		guard await ensureLoaded() else { return }
		await store.resetData(forView: viewIdentifier)
	}

	// MARK: - Termination

	func prepareForTermination() async {
		isTerminating = true
		if let loadTask {
			_ = await loadTask.value
			self.loadTask = nil
		}
		await store.close()
		isLoaded = false
		await requests.cancelAll()
	}
}
