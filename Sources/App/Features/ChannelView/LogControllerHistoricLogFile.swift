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

 The index itself is a value with no reference-typed state; the facade below
 owns the only copies and keeps them on the main actor. */
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
		Self.release(contribution.messageIdentifier, from: &messageIdentifiers)
		Self.release(contribution.fallbackKey, from: &fallbackKeys)
	}

	private mutating func retain(_ contribution: Contribution) {
		if let messageIdentifier = contribution.messageIdentifier {
			messageIdentifiers[messageIdentifier, default: 0] += 1
		}
		if let fallbackKey = contribution.fallbackKey {
			fallbackKeys[fallbackKey, default: 0] += 1
		}
	}

	private static func release(_ key: String?, from counts: inout [String: Int]) {
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
	private let client: HistoricLogClient
	let recovery = TranscriptHistoryRecoveryState()
	private var operations: Task<Void, Never>?
	private enum Termination {
		case none
		case pending([@MainActor @Sendable () -> Void])
	}

	private var termination = Termination.none

	init(client: HistoricLogClient = .shared) {
		self.client = client
	}

	public static func shared() -> LogControllerHistoricLogFile {
		sharedInstance
	}

	// MARK: - Process life cycle

	public func resetMaximumLineCount() {
		Task { await client.applyMaximumLineCount() }
	}

	public func prepareForApplicationTermination(
		completionBlock: (@MainActor @Sendable () -> Void)? = nil
	) {
		if case var .pending(completions) = termination {
			if let completionBlock {
				completions.append(completionBlock)
			}
			termination = .pending(completions)
			return
		}
		termination = .pending(completionBlock.map { [$0] } ?? [])
		let predecessor = operations
		operations = Task { @MainActor in
			await predecessor?.value
			let result = await client.prepareForTermination()
			if case let .failed(reason) = result {
				recovery.storageFailure = reason
				return
			}
			if case let .pending(completions) = termination {
				termination = .none
				for completion in completions {
					completion()
				}
			}
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
		 millisecond keeps a value parsed twice from the same string equal.

		 A date so far from the epoch that its millisecond count leaves `Int64`
		 cannot have been written by anything that reads it back, so it gets no
		 fallback key rather than trapping the conversion. */
		guard let milliseconds = Int64(exactly: (date.timeIntervalSince1970 * 1000.0).rounded()) else {
			return nil
		}
		return String(format: "%lld\u{001f}%@\u{001f}%@", milliseconds, nickname ?? "", messageBody)
	}

	public func indexLogLine(_ logLine: LogLine, forView viewIdentifier: String) {
		let messageIdentifier = logLine.messageIdentifier

		viewIndexes[viewIdentifier, default: HistoricLogViewIndex()].add(
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

		let newestDate = viewIndexes[viewIdentifier]?.newestDate ?? receivedAt
		viewIndexes[viewIdentifier]?.newestDate = max(newestDate, receivedAt)
	}

	public func indexLogLines(_ logLines: [LogLine], forView viewIdentifier: String) {
		for logLine in logLines {
			indexLogLine(logLine, forView: viewIdentifier)
		}
	}

	/// Withdraws the lines the store has pruned from the view's index.
	func forgetLines(_ uniqueIdentifiers: [String], inView viewIdentifier: String) {
		for uniqueIdentifier in uniqueIdentifiers {
			viewIndexes[viewIdentifier]?.remove(uniqueIdentifier)
		}
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

	// MARK: - Writing

	public func writeNewEntry(with logLine: LogLine, forView viewIdentifier: String) {
		let entry = logLine.historicEntry(forView: viewIdentifier)
		let predecessor = operations
		operations = Task {
			await predecessor?.value
			switch await client.writeEntry(entry) {
			case .accepted: indexLogLine(logLine, forView: viewIdentifier)
			case .unavailable: recovery.storageFailure = PromptStrings.Logging.scrollbackFailureBody
			case let .failed(reason): recovery.storageFailure = reason
			}
		}
	}

	@discardableResult
	public func forgetView(_ viewIdentifier: String) -> Task<Void, Never> {
		let predecessor = operations
		let operation = Task {
			await predecessor?.value
			switch await client.forgetView(viewIdentifier) {
			case .deleted:
				viewIndexes.removeValue(forKey: viewIdentifier)
				recovery.deletionFailures.removeValue(forKey: viewIdentifier)
			case let .failed(reason): recovery.deletionFailures[viewIdentifier] = reason
			case .unavailable: recovery.deletionFailures[viewIdentifier] = PromptStrings.Logging.scrollbackFailureBody
			}
		}
		operations = operation
		return operation
	}

	@discardableResult
	public func resetData(forView viewIdentifier: String) -> Task<Void, Never> {
		let predecessor = operations
		let operation = Task {
			await predecessor?.value
			switch await client.resetData(forView: viewIdentifier) {
			case .deleted:
				viewIndexes.removeValue(forKey: viewIdentifier)
				recovery.deletionFailures.removeValue(forKey: viewIdentifier)
			case let .failed(reason): recovery.deletionFailures[viewIdentifier] = reason
			case .unavailable: recovery.deletionFailures[viewIdentifier] = PromptStrings.Logging.scrollbackFailureBody
			}
		}
		operations = operation
		return operation
	}

	func retryLoading() async -> Bool {
		await operations?.value
		guard await client.retryLoading() else { return false }
		switch await client.saveData() {
		case .saved:
			if case let .pending(completions) = termination {
				if case let .failed(reason) = await client.prepareForTermination() {
					recovery.storageFailure = reason
					return false
				}
				termination = .none
				recovery.storageFailure = nil
				for completion in completions {
					completion()
				}
			} else {
				recovery.storageFailure = nil
			}
			return true
		case let .failed(reason): recovery.storageFailure = reason; return false
		}
	}

	func fetchOutcome(_ request: HistoricLogFetchRequest) async -> HistoricLogFetchOutcome {
		await operations?.value
		return await client.fetchOutcome(request)
	}
}
