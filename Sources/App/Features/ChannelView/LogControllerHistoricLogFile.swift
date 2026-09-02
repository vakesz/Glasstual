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
 history replayed by the server can be checked against the local scrollback.
 The index is filled from every line written and every line fetched, and
 withdrawn again when the store prunes the row behind it — otherwise it would
 hold a second copy of every message the process has ever seen.

 The two lookups are counted rather than set-valued: two lines can carry the
 same body at the same second from the same nickname, and dropping one of them
 must not make the other invisible to the duplicate check.

 Decoding happens on the main actor, so the value belongs there and needs no
 synchronisation. */
private nonisolated struct HistoricLogViewIndex: Sendable { // nonisolated: value
	/// What one indexed line contributed, so the contribution can be withdrawn
	/// when the line goes. `nil` where the line carried no such value.
	struct Contribution: Sendable {
		var messageIdentifier: String?
		var fallbackKey: String?
	}

	private(set) var messageIdentifiers: [String: Int] = [:]
	private(set) var fallbackKeys: [String: Int] = [:]
	private var contributions: [String: Contribution] = [:]
	var newestDate: Date?

	/// Records what `uniqueIdentifier` contributes. A line the index already
	/// holds is left alone: the same row is indexed again on every fetch.
	mutating func add(
		_ contribution: Contribution,
		for uniqueIdentifier: String
	) {
		guard uniqueIdentifier.isEmpty == false else {
			retain(contribution)
			return
		}
		guard contributions[uniqueIdentifier] == nil else { return }
		contributions[uniqueIdentifier] = contribution
		retain(contribution)
	}

	/// Withdraws what a pruned line contributed.
	mutating func remove(_ uniqueIdentifier: String) {
		guard let contribution = contributions.removeValue(forKey: uniqueIdentifier) else { return }
		release(contribution.messageIdentifier, from: &messageIdentifiers)
		release(contribution.fallbackKey, from: &fallbackKeys)
	}

	private mutating func retain(_ contribution: Contribution) {
		if let messageIdentifier = contribution.messageIdentifier {
			messageIdentifiers[messageIdentifier, default: 0] += 1
		}
		if let fallbackKey = contribution.fallbackKey {
			fallbackKeys[fallbackKey, default: 0] += 1
		}
	}

	private func release(_ key: String?, from counts: inout [String: Int]) {
		guard let key, let count = counts[key] else { return }
		if count <= 1 {
			counts.removeValue(forKey: key)
		} else {
			counts[key] = count - 1
		}
	}
}

/** The main-actor facade for scrollback history.

 It owns the duplicate index — main-actor state, read synchronously by the IRC
 layer when it decides whether a replayed history line is one it already has —
 and forwards storage work to `HistoricLogClient`. */
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

	/// Raised when the store cannot open its database.
	static func reportConnectionFailure(_ message: String) {
		Alerts.alert(
			withMessage: message,
			title: PromptStrings.Logging.scrollbackFailureTitle,
			defaultButton: PromptStrings.Action.confirmation,
			alternateButton: nil
		)
	}

	/// The store is about to drop these lines. The duplicate index is pruned
	/// first, and unconditionally: it outlives any view controller.
	static func noteWillDeleteLines(_ uniqueIdentifiers: [String], inView viewIdentifier: String) {
		shared().forgetLines(uniqueIdentifiers, inView: viewIdentifier)

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
		let messageIdentifier = logLine.messageIdentifier

		index.add(
			HistoricLogViewIndex.Contribution(
				messageIdentifier: messageIdentifier?.isEmpty == false ? messageIdentifier : nil,
				fallbackKey: Self.fallbackKey(
					for: logLine.receivedAt,
					nickname: logLine.nickname,
					messageBody: logLine.messageBody
				)
			),
			for: logLine.uniqueIdentifier
		)

		let receivedAt = logLine.receivedAt

		if let newestDate = index.newestDate {
			index.newestDate = max(newestDate, receivedAt)
		} else {
			index.newestDate = receivedAt
		}

		viewIndexes[viewIdentifier] = index
	}

	public func indexLogLines(_ logLines: [LogLine], forView viewIdentifier: String) {
		for logLine in logLines {
			indexLogLine(logLine, forView: viewIdentifier)
		}
	}

	/// Withdraws the lines the store has pruned from the view's index.
	func forgetLines(_ uniqueIdentifiers: [String], inView viewIdentifier: String) {
		guard var index = viewIndexes[viewIdentifier] else { return }

		for uniqueIdentifier in uniqueIdentifiers {
			index.remove(uniqueIdentifier)
		}

		viewIndexes[viewIdentifier] = index
	}

	public func containsMessageIdentifier(_ messageIdentifier: String, forView viewIdentifier: String) -> Bool {
		viewIndexes[viewIdentifier]?.messageIdentifiers[messageIdentifier] != nil
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

		return index.fallbackKeys[fallbackKey] != nil
	}

	public func newestLineDate(forView viewIdentifier: String) -> Date? {
		viewIndexes[viewIdentifier]?.newestDate
	}

	// MARK: - Fetching

	/// Decodes fetched rows and records them in the index. The rows cross the
	/// XPC boundary as values; the log lines they decode into are main-actor.
	func decodeAndIndex(_ historicEntries: [HistoricLogEntry], forView viewIdentifier: String) -> [LogLine] {
		let logLines = HistoricLogClient.logLines(from: historicEntries)
		indexLogLines(logLines, forView: viewIdentifier)
		return logLines
	}

	// MARK: - Writing

	public func writeNewEntry(with logLine: LogLine, forView viewIdentifier: String) {
		indexLogLine(logLine, forView: viewIdentifier)

		let entry = logLine.historicEntry(forView: viewIdentifier)
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
