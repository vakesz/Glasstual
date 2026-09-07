/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import Foundation
@testable import Glasstual
import Testing

/** The in-memory index that answers "do we already have this line?".

 It holds a copy of every message body it is given, so it has to shrink again
 when the store prunes the rows behind those bodies — otherwise a long-running
 process accumulates a second copy of every message it has ever seen. */
@MainActor
@Suite("Historic log duplicate index")
struct HistoricLogDuplicateIndexTests {
	private func logLine(body: String, messageIdentifier: String, at date: Date) -> LogLine {
		var line = LogLine()
		line.messageBody = body
		line.nickname = "alice"
		line.receivedAt = date
		line.messageIdentifier = messageIdentifier
		line.lineType = .privateMessage
		return line
	}

	@Test("A pruned line is withdrawn from the index it was added to")
	func pruningWithdrawsTheLine() {
		let index = LogControllerHistoricLogFile.shared()
		let view = "view-\(UUID().uuidString)"
		let date = Date()
		let line = logLine(body: "hello", messageIdentifier: "msg-1", at: date)
		defer { index.forgetView(view) }

		index.indexLogLine(line, forView: view)

		#expect(index.containsMessageIdentifier("msg-1", forView: view))
		#expect(index.containsLine(receivedAt: date, nickname: "alice", messageBody: "hello", forView: view))

		LogControllerHistoricLogFile.noteWillDeleteLines([line.uniqueIdentifier], inView: view)

		#expect(index.containsMessageIdentifier("msg-1", forView: view) == false)
		#expect(
			index.containsLine(receivedAt: date, nickname: "alice", messageBody: "hello", forView: view) == false
		)
	}

	/// Two lines can carry the same body from the same nickname in the same
	/// millisecond, and pruning one of them must not make the other invisible.
	@Test("Pruning one of two identical lines leaves the other findable")
	func pruningOneOfTwoIdenticalLinesKeepsTheOther() {
		let index = LogControllerHistoricLogFile.shared()
		let view = "view-\(UUID().uuidString)"
		let date = Date()
		let first = logLine(body: "same", messageIdentifier: "msg-1", at: date)
		let second = logLine(body: "same", messageIdentifier: "msg-2", at: date)
		defer { index.forgetView(view) }

		index.indexLogLines([first, second], forView: view)
		LogControllerHistoricLogFile.noteWillDeleteLines([first.uniqueIdentifier], inView: view)

		#expect(index.containsMessageIdentifier("msg-1", forView: view) == false)
		#expect(index.containsMessageIdentifier("msg-2", forView: view))
		#expect(index.containsLine(receivedAt: date, nickname: "alice", messageBody: "same", forView: view))

		LogControllerHistoricLogFile.noteWillDeleteLines([second.uniqueIdentifier], inView: view)

		#expect(
			index.containsLine(receivedAt: date, nickname: "alice", messageBody: "same", forView: view) == false
		)
	}

	/// The same row is indexed again on every fetch that returns it, and a line
	/// counted twice would survive its own deletion.
	@Test("Indexing the same line twice still leaves one entry to withdraw")
	func reindexingDoesNotDoubleCount() {
		let index = LogControllerHistoricLogFile.shared()
		let view = "view-\(UUID().uuidString)"
		let date = Date()
		let line = logLine(body: "hello", messageIdentifier: "msg-1", at: date)
		defer { index.forgetView(view) }

		index.indexLogLine(line, forView: view)
		index.indexLogLine(line, forView: view)

		LogControllerHistoricLogFile.noteWillDeleteLines([line.uniqueIdentifier], inView: view)

		#expect(index.containsMessageIdentifier("msg-1", forView: view) == false)
		#expect(
			index.containsLine(receivedAt: date, nickname: "alice", messageBody: "hello", forView: view) == false
		)
	}

	/** The fallback key rounds a timestamp to whole milliseconds. A date far
	 enough from the epoch that the count leaves `Int64` has no key, and asking
	 for one must answer "not indexed" rather than trap the conversion. */
	@Test("A timestamp beyond the millisecond range is indexed without a fallback key")
	func unrepresentableTimestampHasNoFallbackKey() {
		let index = LogControllerHistoricLogFile()
		let view = "view-\(UUID().uuidString)"
		let date = Date(timeIntervalSince1970: 1e40)
		let line = logLine(body: "hello", messageIdentifier: "msg-1", at: date)

		index.indexLogLine(line, forView: view)

		#expect(index.containsMessageIdentifier("msg-1", forView: view))
		#expect(index.containsLine(receivedAt: date, nickname: "alice", messageBody: "hello", forView: view) == false)
		#expect(index.newestLineDate(forView: view) == date)
	}

	@Test("Shared identifiers remain counted across repeated indexing and pruning")
	func sharedIdentifiersAreCountedUntilLastPrune() {
		let index = LogControllerHistoricLogFile()
		let view = "view-\(UUID().uuidString)"
		let date = Date(timeIntervalSince1970: 1000)
		let first = logLine(body: "same", messageIdentifier: "shared", at: date)
		let second = logLine(body: "same", messageIdentifier: "shared", at: date)
		let newest = logLine(body: "newest", messageIdentifier: "newest", at: date.addingTimeInterval(1))

		index.indexLogLines([newest, first, second, first, second], forView: view)
		#expect(index.newestLineDate(forView: view) == newest.receivedAt)
		index.forgetLines([first.uniqueIdentifier, first.uniqueIdentifier, "missing"], inView: view)
		#expect(index.containsMessageIdentifier("shared", forView: view))
		#expect(index.containsLine(receivedAt: date, nickname: "alice", messageBody: "same", forView: view))

		index.forgetLines([second.uniqueIdentifier], inView: view)
		#expect(index.containsMessageIdentifier("shared", forView: view) == false)
		#expect(index.containsLine(receivedAt: date, nickname: "alice", messageBody: "same", forView: view) == false)
		#expect(index.containsMessageIdentifier("newest", forView: view))
	}
}
