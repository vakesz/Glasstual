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

/** What the app knows about the lines of one view, kept in memory so that chat
 history replayed by the server can be checked against the local scrollback
 without a round trip to the XPC service. The index is filled from every line
 written and every line fetched.

 A value: it used to be a lock-guarded object because the XPC reply queue
 indexed fetched lines. Decoding now happens on the main actor, so the index
 belongs to the main actor and needs no synchronisation at all. */
private nonisolated struct HistoricLogViewIndex: Sendable { // nonisolated: value
	var messageIdentifiers: Set<String> = []
	var fallbackKeys: Set<String> = []
	var newestDate: Date?
	var oldestDate: Date?
}

/** The app's side of the scrollback history service.

 It owns the duplicate index — main-actor state, read synchronously by the IRC
 layer when it decides whether a replayed history line is one it already has —
 and forwards everything else to `HistoricLogClient`, which owns the connection. */
@MainActor
public final class LogControllerHistoricLogFile {
	public static let sharedInstance = LogControllerHistoricLogFile()

	private var viewIndexes: [String: HistoricLogViewIndex] = [:]

	public static func shared() -> LogControllerHistoricLogFile {
		sharedInstance
	}

	// MARK: - Process life cycle

	public func resetMaximumLineCount() {
		Task { await HistoricLogClient.shared.applyMaximumLineCount() }
	}

	public func prepareForApplicationTermination(
		completionBlock: (@MainActor @Sendable () -> Void)? = nil
	) {
		Task { @MainActor in
			await HistoricLogClient.shared.prepareForTermination()
			completionBlock?()
		}
	}

	/// Raised when the connection dies for a reason the user should know about.
	/// The client awaits this instead of hopping through a detached task.
	static func reportConnectionFailure(_ message: String) {
		TDCAlert.alert(
			withMessage: message,
			title: PromptStrings.Logging.scrollbackFailureTitle,
			defaultButton: PromptStrings.Action.confirmation,
			alternateButton: nil
		)
	}

	/// The service is about to drop these lines from its store.
	static func noteWillDeleteLines(_ uniqueIdentifiers: [String], inView viewIdentifier: String) {
		guard let item = AppController.shared.world?.findItem(withId: viewIdentifier) else {
			return
		}

		item.logController?.notifyHistoricLogWillDeleteLines(uniqueIdentifiers)
	}

	// MARK: - Duplicate index

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

	public func indexLogLine(_ logLine: LogLine, forView viewIdentifier: String) {
		var index = viewIndexes[viewIdentifier] ?? HistoricLogViewIndex()

		if let messageIdentifier = logLine.messageIdentifier, messageIdentifier.isEmpty == false {
			index.messageIdentifiers.insert(messageIdentifier)
		}

		if let fallbackKey = Self.fallbackKey(
			for: logLine.receivedAt,
			nickname: logLine.nickname,
			messageBody: logLine.messageBody
		) {
			index.fallbackKeys.insert(fallbackKey)
		}

		let receivedAt = logLine.receivedAt

		if let newestDate = index.newestDate {
			index.newestDate = max(newestDate, receivedAt)
		} else {
			index.newestDate = receivedAt
		}

		if let oldestDate = index.oldestDate {
			index.oldestDate = min(oldestDate, receivedAt)
		} else {
			index.oldestDate = receivedAt
		}

		viewIndexes[viewIdentifier] = index
	}

	public func indexLogLines(_ logLines: [LogLine], forView viewIdentifier: String) {
		for logLine in logLines {
			indexLogLine(logLine, forView: viewIdentifier)
		}
	}

	public func containsMessageIdentifier(_ messageIdentifier: String, forView viewIdentifier: String) -> Bool {
		viewIndexes[viewIdentifier]?.messageIdentifiers.contains(messageIdentifier) ?? false
	}

	public func containsLine(
		receivedAt: Date,
		nickname: String?,
		messageBody: String,
		forView viewIdentifier: String
	) -> Bool {
		guard let index = viewIndexes[viewIdentifier],
		      let fallbackKey = Self.fallbackKey(
		      	for: receivedAt,
		      	nickname: nickname,
		      	messageBody: messageBody
		      )
		else {
			return false
		}

		return index.fallbackKeys.contains(fallbackKey)
	}

	public func newestLineDate(forView viewIdentifier: String) -> Date? {
		viewIndexes[viewIdentifier]?.newestDate
	}

	public func oldestLineDate(forView viewIdentifier: String) -> Date? {
		viewIndexes[viewIdentifier]?.oldestDate
	}

	// MARK: - Fetching

	/// Decodes fetched rows and records them in the index. The rows cross the
	/// XPC boundary as values; the log lines they decode into are main-actor.
	func decodeAndIndex(_ xpcObjects: [LogLineXPC], forView viewIdentifier: String) -> [LogLine] {
		let logLines = HistoricLogClient.logLines(from: xpcObjects)
		indexLogLines(logLines, forView: viewIdentifier)
		return logLines
	}

	// MARK: - Writing

	public func writeNewEntry(with logLine: LogLine, forView viewIdentifier: String) {
		indexLogLine(logLine, forView: viewIdentifier)

		let entry = logLine.xpcObject(forView: viewIdentifier)
		Task { await HistoricLogClient.shared.writeEntry(entry) }
	}

	public func forgetView(_ viewIdentifier: String) {
		viewIndexes.removeValue(forKey: viewIdentifier)
		Task { await HistoricLogClient.shared.forgetView(viewIdentifier) }
	}

	public func resetData(forView viewIdentifier: String) {
		viewIndexes.removeValue(forKey: viewIdentifier)
		Task { await HistoricLogClient.shared.resetData(forView: viewIdentifier) }
	}
}
