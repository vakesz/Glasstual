/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \\ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\\___/_/\\_\\__|\\__,_|\\__,_|_|
 *
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 *********************************************************************** */

import CocoaExtensions
import Foundation
import os

private let historicLogLogger = Logger(
	subsystem: Bundle.main.bundleIdentifier ?? "Glasstual",
	category: "HistoricLog"
)

/** What the client knows about the lines of one view, kept in memory so
 that chat history replayed by the server can be checked against the
 local scrollback without a round trip to the XPC service. The index is
 filled from every line written and every line fetched. */
private final class LogControllerHistoricLogViewIndex: NSObject {
	let messageIdentifiers = NSMutableSet()
	let fallbackKeys = NSMutableSet()
	var newestDate: Date?
	var oldestDate: Date?
}

/* ISOLATION-EXCEPTION: `HistoricLogClientProtocol` is an XPC protocol whose
 callbacks arrive on the connection's queue, so this type cannot be isolated. Its
 mutable state is guarded by `processStateLock`. Owned by the XPC-service task. */
@objc(TVCLogControllerHistoricLogFile)
public final class LogControllerHistoricLogFile: NSObject, HistoricLogClientProtocol, @unchecked Sendable {
	private let viewIndexes = NSMutableDictionary()
	private let processStateLock = NSLock()
	@objc public private(set) var isSaving = false
	private var isTerminating = false
	private var processLoaded = false
	private var processLoading = false
	private var serviceConnection: NSXPCConnection?
	private var connectionInvalidatedVoluntarily = false
	private var didShowConnectionError = false
	private var lastServiceConnectionError: Error?
	private var terminationCompletionBlock: (() -> Void)?

	@objc(sharedInstance)
	public static func shared() -> LogControllerHistoricLogFile {
		enum Storage {
			static let instance = LogControllerHistoricLogFile()
		}
		return Storage.instance
	}

	override public init() {
		super.init()
	}

	private var databaseSavePath: String? {
		PathInfo.groupContainerApplicationCaches
	}

	private func warmProcessIfNeeded() {
		processStateLock.lock()
		defer { processStateLock.unlock() }

		if processLoading || processLoaded {
			return
		}

		historicLogLogger.debug("Warming process...")
		processLoading = true
		connectToService()
		openDatabase()
		resetMaximumLineCount()
	}

	private func invalidateProcess() {
		processStateLock.lock()
		defer { processStateLock.unlock() }

		if processLoading == false, processLoaded == false {
			return
		}

		historicLogLogger.debug("Invalidating process...")
		connectionInvalidatedVoluntarily = true
		serviceConnection?.invalidate()
	}

	private func openDatabase() {
		guard let databaseSavePath else {
			processLoading = false
			processLoaded = false
			return
		}

		remoteObjectProxy(withErrorHandler: { [weak self] _ in
			self?.setProcessLoadState(loading: false, loaded: false)
			historicLogLogger.error("Failed to communicate with process to open database")
		})?.openDatabase(
			inDirectory: databaseSavePath,
			withCompletionBlock: { [weak self] success in
				if success {
					historicLogLogger.debug("Successfully opened database")
				} else {
					historicLogLogger.error("Failed to open database")
				}

				self?.setProcessLoadState(loading: false, loaded: success)
			}
		)
	}

	private func connectToService() {
		let serviceConnection = NSXPCConnection(
			serviceName: "com.vakesz.glasstual.ScrollbackHistoryManager"
		)

		let remoteObjectInterface = NSXPCInterface(with: HistoricLogServerProtocol.self)
		guard HistoricLogInterface.configure(remoteObjectInterface) else {
			return
		}

		serviceConnection.remoteObjectInterface = remoteObjectInterface
		serviceConnection.exportedInterface = NSXPCInterface(with: HistoricLogClientProtocol.self)
		serviceConnection.exportedObject = self

		serviceConnection.interruptionHandler = { [weak self] in
			performSynchronouslyOnMainQueue {
				self?.interruptionHandler()
			}
			historicLogLogger.log("Interruption handler called")
		}

		serviceConnection.invalidationHandler = { [weak self] in
			performSynchronouslyOnMainQueue {
				self?.invalidationHandler()
			}
			historicLogLogger.log("Invalidation handler called")
		}

		serviceConnection.resume()
		self.serviceConnection = serviceConnection
	}

	private func interruptionHandler() {
		invalidateProcess()
	}

	private func invalidationHandler() {
		serviceConnection = nil
		resetContext()

		if isTerminating {
			invokeTerminationCompletionBlock()
		}

		if connectionInvalidatedVoluntarily {
			connectionInvalidatedVoluntarily = false
			return
		}

		if didShowConnectionError == false {
			didShowConnectionError = true
		} else {
			return
		}

		var lastErrorMessage = lastServiceConnectionError?.localizedDescription ?? ""
		if lastErrorMessage.isEmpty == false {
			lastErrorMessage = PromptStrings.Logging.lastError(lastErrorMessage)
		}

		_ = TDCAlert.alert(
			withMessage: lastErrorMessage,
			title: PromptStrings.Logging.scrollbackFailureTitle,
			defaultButton: PromptStrings.Action.confirmation,
			alternateButton: nil
		)
	}

	private func resetContext() {
		processStateLock.lock()
		defer { processStateLock.unlock() }

		isSaving = false
		processLoading = false
		processLoaded = false
	}

	private func setProcessLoadState(loading: Bool, loaded: Bool) {
		processStateLock.lock()
		defer { processStateLock.unlock() }

		processLoading = loading
		processLoaded = loaded
	}

	@objc
	public func resetMaximumLineCount() {
		let maximumLineCount = TextualPreferences.scrollbackSaveLimit()
		remoteObjectProxy()?.setMaximumLineCount(maximumLineCount)
	}

	@objc
	public func prepareForApplicationTermination() {
		prepareForApplicationTermination(completionBlock: nil)
	}

	@objc(prepareForApplicationTerminationWithCompletionBlock:)
	public func prepareForApplicationTermination(completionBlock: (() -> Void)?) {
		isTerminating = true
		terminationCompletionBlock = completionBlock

		if saveData() == false {
			invokeTerminationCompletionBlock()
		}
	}

	private func invokeTerminationCompletionBlock() {
		guard let completionBlock = terminationCompletionBlock else {
			return
		}

		terminationCompletionBlock = nil
		performAsynchronouslyOnMainQueue(completionBlock)
	}

	private func remoteObjectProxy() -> HistoricLogServerProtocol? {
		remoteObjectProxy(withErrorHandler: nil)
	}

	private func remoteObjectProxy(
		withErrorHandler handler: ((Error) -> Void)?
	) -> HistoricLogServerProtocol? {
		serviceConnection?.remoteObjectProxyWithErrorHandler { [weak self] error in
			self?.lastServiceConnectionError = error
			historicLogLogger.error(
				"Error occurred while communicating with service: \(error.localizedDescription, privacy: .public)"
			)
			handler?(error)
		} as? HistoricLogServerProtocol
	}

	private func logLines(from xpcObjects: [LogLineXPC], for item: IRCTreeItem) -> [LogLine] {
		var logLines: [LogLine] = []
		logLines.reserveCapacity(xpcObjects.count)

		for xpcObject in xpcObjects {
			guard let logLine = LogLine.logLine(from: xpcObject) else {
				historicLogLogger.error(
					"Failed to initialize object \(String(describing: xpcObject), privacy: .public). Corrupt data?"
				)
				continue
			}

			indexLogLine(logLine, for: item)
			logLines.append(logLine)
		}

		return logLines
	}

	private func viewIndex(for item: IRCTreeItem, create: Bool) -> LogControllerHistoricLogViewIndex? {
		guard let viewId = item.uniqueIdentifier as String? else {
			return nil
		}

		objc_sync_enter(viewIndexes)
		defer { objc_sync_exit(viewIndexes) }

		if let index = viewIndexes[viewId] as? LogControllerHistoricLogViewIndex {
			return index
		}

		guard create else {
			return nil
		}

		let index = LogControllerHistoricLogViewIndex()
		viewIndexes[viewId] = index
		return index
	}

	private static func fallbackKey(
		for date: Date?,
		nickname: String?,
		messageBody: String?
	) -> String? {
		guard let date, let messageBody else {
			return nil
		}

		/* Server timestamps carry millisecond precision. Rounding to the
		 millisecond keeps a value parsed twice from the same string equal. */
		let milliseconds = Int64((date.timeIntervalSince1970 * 1000.0).rounded())
		return String(format: "%lld\u{001f}%@\u{001f}%@", milliseconds, nickname ?? "", messageBody)
	}

	@objc(indexLogLine:forItem:)
	public func indexLogLine(_ logLine: LogLine, for item: IRCTreeItem) {
		guard let index = viewIndex(for: item, create: true) else {
			return
		}

		let messageIdentifier = logLine.messageIdentifier
		let fallbackKey = Self.fallbackKey(
			for: logLine.receivedAt,
			nickname: logLine.nickname,
			messageBody: logLine.messageBody
		)
		let receivedAt = logLine.receivedAt

		objc_sync_enter(index)
		defer { objc_sync_exit(index) }

		if let messageIdentifier, messageIdentifier.isEmpty == false {
			index.messageIdentifiers.add(messageIdentifier)
		}

		if let fallbackKey {
			index.fallbackKeys.add(fallbackKey)
		}

		if index.newestDate == nil || receivedAt.compare(index.newestDate!) == .orderedDescending {
			index.newestDate = receivedAt
		}

		if index.oldestDate == nil || receivedAt.compare(index.oldestDate!) == .orderedAscending {
			index.oldestDate = receivedAt
		}
	}

	@objc(containsMessageIdentifier:forItem:)
	public func containsMessageIdentifier(_ messageIdentifier: String, for item: IRCTreeItem) -> Bool {
		guard let index = viewIndex(for: item, create: false) else {
			return false
		}

		objc_sync_enter(index)
		defer { objc_sync_exit(index) }
		return index.messageIdentifiers.contains(messageIdentifier)
	}

	@objc(containsLineReceivedAt:nickname:messageBody:forItem:)
	public func containsLine(
		receivedAt: Date,
		nickname: String?,
		messageBody: String,
		for item: IRCTreeItem
	) -> Bool {
		guard let index = viewIndex(for: item, create: false),
		      let fallbackKey = Self.fallbackKey(
		      	for: receivedAt,
		      	nickname: nickname,
		      	messageBody: messageBody
		      )
		else {
			return false
		}

		objc_sync_enter(index)
		defer { objc_sync_exit(index) }
		return index.fallbackKeys.contains(fallbackKey)
	}

	@objc(newestLineDateForItem:)
	public func newestLineDate(for item: IRCTreeItem) -> Date? {
		guard let index = viewIndex(for: item, create: false) else {
			return nil
		}

		objc_sync_enter(index)
		defer { objc_sync_exit(index) }
		return index.newestDate
	}

	@objc(oldestLineDateForItem:)
	public func oldestLineDate(for item: IRCTreeItem) -> Date? {
		guard let index = viewIndex(for: item, create: false) else {
			return nil
		}

		objc_sync_enter(index)
		defer { objc_sync_exit(index) }
		return index.oldestDate
	}

	private func forgetIndex(for item: IRCTreeItem) {
		guard let viewId = item.uniqueIdentifier as String? else {
			return
		}

		objc_sync_enter(viewIndexes)
		defer { objc_sync_exit(viewIndexes) }
		viewIndexes.removeObject(forKey: viewId)
	}

	@objc(fetchEntriesForItem:ascending:fetchLimit:limitToDate:withCompletionBlock:)
	public func fetchEntries(
		for item: IRCTreeItem,
		ascending: Bool,
		fetchLimit: UInt,
		limitToDate: Date?,
		withCompletionBlock completionBlock: @escaping ([LogLine]) -> Void
	) {
		warmProcessIfNeeded()

		remoteObjectProxy(withErrorHandler: { _ in
			completionBlock([])
		})?.fetchEntries(
			forView: item.uniqueIdentifier,
			ascending: ascending,
			fetchLimit: fetchLimit,
			limitTo: limitToDate,
			withCompletionBlock: { [weak self] entries in
				let logLines = self?.logLines(from: entries, for: item) ?? []
				completionBlock(logLines)
			}
		)
	}

	@objc(fetchEntriesForItem:withUniqueIdentifier:beforeFetchLimit:afterFetchLimit:limitToDate:withCompletionBlock:)
	public func fetchEntries(
		for item: IRCTreeItem,
		withUniqueIdentifier uniqueId: String,
		beforeFetchLimit fetchLimitBefore: UInt,
		afterFetchLimit fetchLimitAfter: UInt,
		limitToDate: Date?,
		withCompletionBlock completionBlock: @escaping ([LogLine]) -> Void
	) {
		warmProcessIfNeeded()

		remoteObjectProxy(withErrorHandler: { _ in
			completionBlock([])
		})?.fetchEntries(
			forView: item.uniqueIdentifier,
			withUniqueIdentifier: uniqueId,
			beforeFetchLimit: fetchLimitBefore,
			afterFetchLimit: fetchLimitAfter,
			limitTo: limitToDate,
			withCompletionBlock: { [weak self] entries in
				let logLines = self?.logLines(from: entries, for: item) ?? []
				completionBlock(logLines)
			}
		)
	}

	@objc(fetchEntriesForItem:beforeUniqueIdentifier:fetchLimit:limitToDate:withCompletionBlock:)
	public func fetchEntries(
		for item: IRCTreeItem,
		beforeUniqueIdentifier uniqueId: String,
		fetchLimit: UInt,
		limitToDate: Date?,
		withCompletionBlock completionBlock: @escaping ([LogLine]) -> Void
	) {
		warmProcessIfNeeded()

		remoteObjectProxy(withErrorHandler: { _ in
			completionBlock([])
		})?.fetchEntries(
			forView: item.uniqueIdentifier,
			beforeUniqueIdentifier: uniqueId,
			fetchLimit: fetchLimit,
			limitTo: limitToDate,
			withCompletionBlock: { [weak self] entries in
				let logLines = self?.logLines(from: entries, for: item) ?? []
				completionBlock(logLines)
			}
		)
	}

	@objc(fetchEntriesForItem:afterUniqueIdentifier:fetchLimit:limitToDate:withCompletionBlock:)
	public func fetchEntries(
		for item: IRCTreeItem,
		afterUniqueIdentifier uniqueId: String,
		fetchLimit: UInt,
		limitToDate: Date?,
		withCompletionBlock completionBlock: @escaping ([LogLine]) -> Void
	) {
		warmProcessIfNeeded()

		remoteObjectProxy(withErrorHandler: { _ in
			completionBlock([])
		})?.fetchEntries(
			forView: item.uniqueIdentifier,
			afterUniqueIdentifier: uniqueId,
			fetchLimit: fetchLimit,
			limitTo: limitToDate,
			withCompletionBlock: { [weak self] entries in
				let logLines = self?.logLines(from: entries, for: item) ?? []
				completionBlock(logLines)
			}
		)
	}

	@objc(fetchEntriesForItem:afterUniqueIdentifier:beforeUniqueIdentifier:fetchLimit:withCompletionBlock:)
	public func fetchEntries(
		for item: IRCTreeItem,
		afterUniqueIdentifier uniqueIdAfter: String,
		beforeUniqueIdentifier uniqueIdBefore: String,
		fetchLimit: UInt,
		withCompletionBlock completionBlock: @escaping ([LogLine]) -> Void
	) {
		warmProcessIfNeeded()

		remoteObjectProxy(withErrorHandler: { _ in
			completionBlock([])
		})?.fetchEntries(
			forView: item.uniqueIdentifier,
			afterUniqueIdentifier: uniqueIdAfter,
			beforeUniqueIdentifier: uniqueIdBefore,
			fetchLimit: fetchLimit,
			withCompletionBlock: { [weak self] entries in
				let logLines = self?.logLines(from: entries, for: item) ?? []
				completionBlock(logLines)
			}
		)
	}

	@objc
	@discardableResult
	public func saveData() -> Bool {
		if isTerminating, processLoaded == false, processLoading == false {
			return false
		}

		if isSaving == false {
			isSaving = true
		} else {
			historicLogLogger.debug("Cancelled save because a save is already saving")
			return true
		}

		warmProcessIfNeeded()

		let saveCompleted: () -> Void = { [weak self] in
			guard let self else {
				return
			}

			isSaving = false

			if isTerminating {
				invalidateProcess()
				invokeTerminationCompletionBlock()
			}
		}

		/* If the service fails while saving, the error handler is the only
		 callback we get. Treat that as the save having ended so that
		 termination is not held up waiting on a reply that never comes. */
		remoteObjectProxy(withErrorHandler: { _ in
			saveCompleted()
		})?.saveData(completionBlock: saveCompleted)

		return true
	}

	@objc(forgetItem:)
	public func forgetItem(_ item: IRCTreeItem) {
		forgetIndex(for: item)
		warmProcessIfNeeded()
		remoteObjectProxy()?.forgetView(item.uniqueIdentifier)
	}

	@objc(resetDataForItem:)
	public func resetData(for item: IRCTreeItem) {
		forgetIndex(for: item)
		warmProcessIfNeeded()
		remoteObjectProxy()?.resetData(forView: item.uniqueIdentifier)
	}

	@objc(writeNewEntryWithLogLine:forItem:)
	public func writeNewEntry(with logLine: LogLine, for item: IRCTreeItem) {
		indexLogLine(logLine, for: item)
		warmProcessIfNeeded()

		let newEntry = logLine.xpcObject(for: item)
		remoteObjectProxy()?.writeLogLine(newEntry)
	}

	@objc(willDeleteUniqueIdentifiers:inView:)
	public func willDeleteUniqueIdentifiers(_ uniqueIdentifiers: [String], inView viewId: String) {
		/* The XPC service does not wait on this, so hop asynchronously rather than
		 blocking its queue on the main thread. */
		Task { @MainActor in
			guard let item = AppController.shared.world?.findItem(withId: viewId) else {
				return
			}

			(item.viewController as AnyObject as? LogController)?
				.notifyHistoricLogWillDeleteLines(uniqueIdentifiers)
		}
	}
}
