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

/// One historic-log fetch, in the shape the service understands. A value, so a
/// request can be queued and replayed without carrying anything isolated.
nonisolated struct HistoricLogFetchRequest: Sendable { // nonisolated: value
	/// Which of the service's five fetches to run.
	enum Kind: Sendable {
		case newest(ascending: Bool, fetchLimit: UInt, limitToDate: Date?)
		case around(uniqueIdentifier: String, before: UInt, after: UInt, limitToDate: Date?)
		case before(uniqueIdentifier: String, fetchLimit: UInt, limitToDate: Date?)
		case after(uniqueIdentifier: String, fetchLimit: UInt, limitToDate: Date?)
		case between(afterUniqueIdentifier: String, beforeUniqueIdentifier: String, fetchLimit: UInt)
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
	typealias Service = @Sendable (HistoricLogFetchRequest) async -> [LogLineXPC]

	/// A request waiting for its turn.
	private nonisolated struct QueuedFetch: Sendable { // nonisolated: value
		let identifier: UUID
		let request: HistoricLogFetchRequest
	}

	/// The caller suspended on a request that has not answered yet.
	private nonisolated struct PendingFetch: Sendable { // nonisolated: value
		let viewIdentifier: String
		let continuation: CheckedContinuation<[LogLineXPC], Never>
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
	func fetch(_ request: HistoricLogFetchRequest) async -> [LogLineXPC] {
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

/** Forwards the service's callbacks into the actor.

 It holds nothing but the actor reference, which is why XPC may call it on
 whichever thread it likes. */
private final nonisolated class HistoricLogClientShim: NSObject, // nonisolated: xpc-shim
	HistoricLogClientProtocol, Sendable
{
	private let client: HistoricLogClient

	init(client: HistoricLogClient) {
		self.client = client
		super.init()
	}

	func willDeleteUniqueIdentifiers( // nonisolated: xpc-shim
		_ uniqueIdentifiers: [String],
		inView viewIdentifier: String
	) {
		Task { await client.handleWillDelete(uniqueIdentifiers, inView: viewIdentifier) }
	}
}

/** Owns the connection to the scrollback history service.

 The connection is created here and never leaves, which is what makes the
 non-`Sendable` `NSXPCConnection` safe without an escape hatch. Everything that
 used to be guarded by `processStateLock` — the warm and invalidate flags, the
 in-flight replies, the termination bookkeeping — is actor state, and every
 reply the service sends comes back through `HistoricLogClientShim`. */
actor HistoricLogClient {
	static let shared = HistoricLogClient()

	private let serviceName: String
	private let databaseDirectory: String?
	private var connection: NSXPCConnection?
	private var connectionCount = 0
	private var shim: HistoricLogClientShim?
	private var isLoading = false
	private var isLoaded = false
	private var isSaving = false
	private var isTerminating = false
	private var invalidatedVoluntarily = false
	private var didReportConnectionFailure = false
	private var lastConnectionError: Error?
	private var inFlight: [UUID: CheckedContinuation<[LogLineXPC], Never>] = [:]
	private var inFlightSaves: [UUID: CheckedContinuation<Void, Never>] = [:]

	private lazy var requests = HistoricLogRequestQueue { [weak self] request in
		await self?.performFetch(request) ?? []
	}

	init(
		serviceName: String = "com.vakesz.glasstual.ScrollbackHistoryManager",
		databaseDirectory: String? = PathInfo.groupContainerApplicationCaches
	) {
		self.serviceName = serviceName
		self.databaseDirectory = databaseDirectory
	}

	/// Whether a connection is currently attached. Test seam.
	var isAttached: Bool {
		connection != nil
	}

	/// How many connections this client has opened over its lifetime. Test seam.
	var connectionsOpened: Int {
		connectionCount
	}

	// MARK: - Decoding

	/// Decodes fetched rows. Pure: it reads nothing but its argument, so it can
	/// run wherever the caller happens to be.
	nonisolated static func logLines(from xpcObjects: [LogLineXPC]) -> [LogLine] { // nonisolated: pure
		xpcObjects.compactMap { xpcObject in
			guard let logLine = LogLine.logLine(from: xpcObject) else {
				historicLogClientLogger.error(
					"Failed to initialize object \(String(describing: xpcObject), privacy: .public). Corrupt data?"
				)
				return nil
			}
			return logLine
		}
	}

	// MARK: - Connection

	/// Connects and opens the database. Idempotent: while a connection is up
	/// and its database is open — or still opening — a second call does nothing.
	/// A failed open is retried on the next call, as it always was.
	func attach() {
		if connection == nil {
			historicLogClientLogger.debug("Warming process...")
			connect()
		}

		guard isLoading == false, isLoaded == false, let databaseDirectory else {
			return
		}

		isLoading = true
		openDatabase(in: databaseDirectory)
		applyMaximumLineCount()
	}

	/// Tears the connection down. Idempotent: detaching twice is one invalidation.
	func detach() {
		guard let connection else {
			return
		}

		historicLogClientLogger.debug("Invalidating process...")
		invalidatedVoluntarily = true
		connection.invalidate()
	}

	private func connect() {
		let connection = NSXPCConnection(serviceName: serviceName)

		let remoteObjectInterface = NSXPCInterface(with: HistoricLogServerProtocol.self)
		guard HistoricLogInterface.configure(remoteObjectInterface) else {
			return
		}

		let shim = HistoricLogClientShim(client: self)
		connection.remoteObjectInterface = remoteObjectInterface
		connection.exportedInterface = NSXPCInterface(with: HistoricLogClientProtocol.self)
		connection.exportedObject = shim

		connection.interruptionHandler = { [weak self] in
			historicLogClientLogger.log("Interruption handler called")
			Task { await self?.handleInterruption() }
		}

		connection.invalidationHandler = { [weak self] in
			historicLogClientLogger.log("Invalidation handler called")
			Task { await self?.handleInvalidation() }
		}

		connection.resume()

		self.connection = connection
		self.shim = shim
		connectionCount += 1
	}

	private func handleInterruption() {
		detach()
	}

	private func handleInvalidation() async {
		connection = nil
		shim = nil
		isSaving = false
		isLoading = false
		isLoaded = false

		/* A caller suspended on a reply that will never arrive has to be let go,
		 or the view it is loading never finishes. */
		failInFlight()
		await requests.cancelAll()
		finishSaves()

		guard invalidatedVoluntarily == false else {
			invalidatedVoluntarily = false
			return
		}

		guard didReportConnectionFailure == false else {
			return
		}
		didReportConnectionFailure = true

		var message = lastConnectionError?.localizedDescription ?? ""
		if message.isEmpty == false {
			message = PromptStrings.Logging.lastError(message)
		}
		await LogControllerHistoricLogFile.reportConnectionFailure(message)
	}

	func handleWillDelete(_ uniqueIdentifiers: [String], inView viewIdentifier: String) async {
		await LogControllerHistoricLogFile.noteWillDeleteLines(uniqueIdentifiers, inView: viewIdentifier)
	}

	private func proxy(onError handler: (@Sendable (Error) -> Void)? = nil) -> HistoricLogServerProtocol? {
		connection?.remoteObjectProxyWithErrorHandler { [weak self] error in
			historicLogClientLogger.error(
				"Error occurred while communicating with service: \(error.localizedDescription, privacy: .public)"
			)
			Task { await self?.noteConnectionError(error) }
			handler?(error)
		} as? HistoricLogServerProtocol
	}

	private func noteConnectionError(_ error: Error) {
		lastConnectionError = error
	}

	// MARK: - Database

	private func openDatabase(in databaseDirectory: String) {
		proxy(onError: { [weak self] _ in
			historicLogClientLogger.error("Failed to communicate with process to open database")
			Task { await self?.noteLoadState(loading: false, loaded: false) }
		})?.openDatabase(inDirectory: databaseDirectory, withCompletionBlock: { [weak self] success in
			if success {
				historicLogClientLogger.debug("Successfully opened database")
			} else {
				historicLogClientLogger.error("Failed to open database")
			}
			Task { await self?.noteLoadState(loading: false, loaded: success) }
		})
	}

	private func noteLoadState(loading: Bool, loaded: Bool) {
		isLoading = loading
		isLoaded = loaded
	}

	/// Pushes the current scrollback save limit to the service.
	func applyMaximumLineCount() {
		proxy()?.setMaximumLineCount(TextualPreferences.scrollbackSaveLimit())
	}

	// MARK: - Fetching

	/// Queues a fetch behind everything already asked for the same view.
	func fetchEntries(_ request: HistoricLogFetchRequest) async -> [LogLineXPC] {
		attach()

		return await requests.fetch(request)
	}

	private func performFetch(_ request: HistoricLogFetchRequest) async -> [LogLineXPC] {
		await withCheckedContinuation { continuation in
			let identifier = UUID()
			inFlight[identifier] = continuation

			let reply: @Sendable ([LogLineXPC]) -> Void = { [weak self] entries in
				Task { await self?.completeFetch(identifier, with: entries) }
			}

			guard let proxy = proxy(onError: { [weak self] _ in
				Task { await self?.completeFetch(identifier, with: []) }
			}) else {
				completeFetch(identifier, with: [])
				return
			}

			send(request, through: proxy, reply: reply)
		}
	}

	private func send(
		_ request: HistoricLogFetchRequest,
		through proxy: HistoricLogServerProtocol,
		reply: @escaping @Sendable ([LogLineXPC]) -> Void
	) {
		let viewIdentifier = request.viewIdentifier

		switch request.kind {
		case let .newest(ascending, fetchLimit, limitToDate):
			proxy.fetchEntries(
				forView: viewIdentifier,
				ascending: ascending,
				fetchLimit: fetchLimit,
				limitTo: limitToDate,
				withCompletionBlock: reply
			)
		case let .around(uniqueIdentifier, before, after, limitToDate):
			proxy.fetchEntries(
				forView: viewIdentifier,
				withUniqueIdentifier: uniqueIdentifier,
				beforeFetchLimit: before,
				afterFetchLimit: after,
				limitTo: limitToDate,
				withCompletionBlock: reply
			)
		case let .before(uniqueIdentifier, fetchLimit, limitToDate):
			proxy.fetchEntries(
				forView: viewIdentifier,
				beforeUniqueIdentifier: uniqueIdentifier,
				fetchLimit: fetchLimit,
				limitTo: limitToDate,
				withCompletionBlock: reply
			)
		case let .after(uniqueIdentifier, fetchLimit, limitToDate):
			proxy.fetchEntries(
				forView: viewIdentifier,
				afterUniqueIdentifier: uniqueIdentifier,
				fetchLimit: fetchLimit,
				limitTo: limitToDate,
				withCompletionBlock: reply
			)
		case let .between(afterUniqueIdentifier, beforeUniqueIdentifier, fetchLimit):
			proxy.fetchEntries(
				forView: viewIdentifier,
				afterUniqueIdentifier: afterUniqueIdentifier,
				beforeUniqueIdentifier: beforeUniqueIdentifier,
				fetchLimit: fetchLimit,
				withCompletionBlock: reply
			)
		}
	}

	/// The error handler and the reply block can both fire; whichever lands
	/// first answers, and the other one finds nothing to answer.
	private func completeFetch(_ identifier: UUID, with entries: [LogLineXPC]) {
		inFlight.removeValue(forKey: identifier)?.resume(returning: entries)
	}

	private func failInFlight() {
		for identifier in inFlight.keys {
			inFlight.removeValue(forKey: identifier)?.resume(returning: [])
		}
	}

	// MARK: - Writing

	func writeEntry(_ entry: LogLineXPC) {
		attach()
		proxy()?.writeLogLine(entry)
	}

	func forgetView(_ viewIdentifier: String) async {
		await requests.forget(view: viewIdentifier)
		attach()
		proxy()?.forgetView(viewIdentifier)
	}

	func resetData(forView viewIdentifier: String) async {
		await requests.forget(view: viewIdentifier)
		attach()
		proxy()?.resetData(forView: viewIdentifier)
	}

	// MARK: - Saving and termination

	@discardableResult
	func saveData() async -> Bool {
		if isTerminating, isLoaded == false, isLoading == false {
			return false
		}

		guard isSaving == false else {
			historicLogClientLogger.debug("Cancelled save because a save is already saving")
			return true
		}

		isSaving = true
		attach()

		await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
			let identifier = UUID()
			inFlightSaves[identifier] = continuation

			/* If the service fails while saving, the error handler is the only
			 callback we get. Treat that as the save having ended so that
			 termination is not held up waiting on a reply that never comes. */
			guard let proxy = proxy(onError: { [weak self] _ in
				Task { await self?.completeSave(identifier) }
			}) else {
				completeSave(identifier)
				return
			}

			proxy.saveData(completionBlock: { [weak self] in
				Task { await self?.completeSave(identifier) }
			})
		}

		isSaving = false
		return true
	}

	private func completeSave(_ identifier: UUID) {
		inFlightSaves.removeValue(forKey: identifier)?.resume()
	}

	private func finishSaves() {
		for identifier in inFlightSaves.keys {
			inFlightSaves.removeValue(forKey: identifier)?.resume()
		}
	}

	/// Saves what is buffered and closes the connection.
	func prepareForTermination() async {
		isTerminating = true

		guard await saveData() else {
			return
		}

		detach()
	}
}
