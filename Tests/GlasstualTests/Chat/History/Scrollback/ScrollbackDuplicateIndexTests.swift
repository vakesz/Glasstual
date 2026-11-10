// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing

/** The in-memory index that answers "do we already have this line?".

 It holds a copy of every message body it is given, so it has to shrink again
 when the store prunes the rows behind those bodies — otherwise a long-running
 process accumulates a second copy of every message it has ever seen. */
@MainActor
@Suite("Scrollback duplicate index")
struct ScrollbackDuplicateIndexTests {
	private func chatLine(body: String, messageIdentifier: String, at date: Date) -> ChatLine {
		var line = ChatLine()
		line.messageBody = body
		line.nickname = "alice"
		line.receivedAt = date
		line.messageIdentifier = messageIdentifier
		line.lineType = .privateMessage
		return line
	}

	@Test("Only server timestamps survive as stored read positions and pruning withdraws them")
	func storedReadPositionUsesServerTime() {
		let index = ScrollbackDuplicateIndex()
		let timestamp = Date(timeIntervalSince1970: 100)
		var stamped = chatLine(body: "server time without msgid", messageIdentifier: "", at: timestamp)
		stamped.serverTimestamp = timestamp
		let local = chatLine(body: "msgid without time", messageIdentifier: "identified", at: timestamp.addingTimeInterval(60))
		index.indexChatLines([stamped, local], forView: "read-position")
		#expect(index.newestReadMarkerTimestamp(forView: "read-position") == timestamp)
		index.forgetLines([stamped.uniqueIdentifier], inView: "read-position")
		#expect(index.newestReadMarkerTimestamp(forView: "read-position") == nil)
		#expect(index.newestConversationLineDate(forView: "read-position") == local.receivedAt)
	}

	@Test("A pruned line is withdrawn from the index it was added to")
	func pruningWithdrawsTheLine() {
		let history = Scrollback.shared
		let index = history.duplicates
		let view = "view-\(UUID().uuidString)"
		let date = Date()
		let line = chatLine(body: "hello", messageIdentifier: "msg-1", at: date)
		defer { history.removeHistory(forView: view, forget: true) }

		index.indexChatLine(line, forView: view)

		#expect(index.containsMessageIdentifier("msg-1", forView: view))
		#expect(index.containsLine(receivedAt: date, nickname: "alice", messageBody: "hello", forView: view))

		Scrollback.noteWillDeleteLines([line.uniqueIdentifier], inView: view)

		#expect(index.containsMessageIdentifier("msg-1", forView: view) == false)
		#expect(
			index.containsLine(receivedAt: date, nickname: "alice", messageBody: "hello", forView: view) == false
		)
	}

	/// Two lines can carry the same body from the same nickname in the same
	/// millisecond, and pruning one of them must not make the other invisible.
	@Test("Pruning one of two identical lines leaves the other findable")
	func pruningOneOfTwoIdenticalLinesKeepsTheOther() {
		let history = Scrollback.shared
		let index = history.duplicates
		let view = "view-\(UUID().uuidString)"
		let date = Date()
		let first = chatLine(body: "same", messageIdentifier: "msg-1", at: date)
		let second = chatLine(body: "same", messageIdentifier: "msg-2", at: date)
		defer { history.removeHistory(forView: view, forget: true) }

		index.indexChatLines([first, second], forView: view)
		Scrollback.noteWillDeleteLines([first.uniqueIdentifier], inView: view)

		#expect(index.containsMessageIdentifier("msg-1", forView: view) == false)
		#expect(index.containsMessageIdentifier("msg-2", forView: view))
		#expect(index.containsLine(receivedAt: date, nickname: "alice", messageBody: "same", forView: view))

		Scrollback.noteWillDeleteLines([second.uniqueIdentifier], inView: view)

		#expect(
			index.containsLine(receivedAt: date, nickname: "alice", messageBody: "same", forView: view) == false
		)
	}

	/// The same row is indexed again on every fetch that returns it, and a line
	/// counted twice would survive its own deletion.
	@Test("Indexing the same line twice still leaves one entry to withdraw")
	func reindexingDoesNotDoubleCount() {
		let history = Scrollback.shared
		let index = history.duplicates
		let view = "view-\(UUID().uuidString)"
		let date = Date()
		let line = chatLine(body: "hello", messageIdentifier: "msg-1", at: date)
		defer { history.removeHistory(forView: view, forget: true) }

		index.indexChatLine(line, forView: view)
		index.indexChatLine(line, forView: view)

		Scrollback.noteWillDeleteLines([line.uniqueIdentifier], inView: view)

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
		let index = ScrollbackDuplicateIndex()
		let view = "view-\(UUID().uuidString)"
		let date = Date(timeIntervalSince1970: 1e40)
		let line = chatLine(body: "hello", messageIdentifier: "msg-1", at: date)

		index.indexChatLine(line, forView: view)

		#expect(index.containsMessageIdentifier("msg-1", forView: view))
		#expect(index.containsLine(receivedAt: date, nickname: "alice", messageBody: "hello", forView: view) == false)
		#expect(index.newestLineDate(forView: view) == date)
	}

	/** A read marker is answered against what a person said. The index keeps
	 both dates because a history request asks for the newest line of any kind,
	 while the badge may only count conversation. */
	@Test("The newest conversation date ignores the events a join narrates")
	func newestConversationDateIgnoresNarratedEvents() {
		let index = ScrollbackDuplicateIndex()
		let view = "view-\(UUID().uuidString)"
		let said = Date(timeIntervalSince1970: 1000)
		var topic = chatLine(body: "the topic", messageIdentifier: "topic-1", at: said.addingTimeInterval(60))
		topic.lineType = .topic
		var mode = chatLine(body: "+nt", messageIdentifier: "mode-1", at: said.addingTimeInterval(120))
		mode.lineType = .mode

		index.indexChatLines([
			chatLine(body: "hello", messageIdentifier: "msg-1", at: said),
			topic,
			mode,
		], forView: view)

		#expect(index.newestLineDate(forView: view) == mode.receivedAt)
		#expect(index.newestConversationLineDate(forView: view) == said)
	}

	/// A view holding nothing but narrated events has no conversation date at
	/// all, which is what leaves a freshly joined channel unbadged.
	@Test("A view of narrated events alone has no newest conversation date")
	func narratedEventsAloneLeaveNoConversationDate() {
		let index = ScrollbackDuplicateIndex()
		let view = "view-\(UUID().uuidString)"
		var join = chatLine(body: "joined", messageIdentifier: "join-1", at: Date(timeIntervalSince1970: 1000))
		join.lineType = .join

		index.indexChatLine(join, forView: view)

		#expect(index.newestLineDate(forView: view) == join.receivedAt)
		#expect(index.newestConversationLineDate(forView: view) == nil)
	}

	@Test("Shared identifiers remain counted across repeated indexing and pruning")
	func sharedIdentifiersAreCountedUntilLastPrune() {
		let index = ScrollbackDuplicateIndex()
		let view = "view-\(UUID().uuidString)"
		let date = Date(timeIntervalSince1970: 1000)
		let first = chatLine(body: "same", messageIdentifier: "shared", at: date)
		let second = chatLine(body: "same", messageIdentifier: "shared", at: date)
		let newest = chatLine(body: "newest", messageIdentifier: "newest", at: date.addingTimeInterval(1))

		index.indexChatLines([newest, first, second, first, second], forView: view)
		#expect(index.newestLineDate(forView: view) == newest.receivedAt)
		index.forgetLines([first.uniqueIdentifier, first.uniqueIdentifier, "missing"], inView: view)
		#expect(index.containsMessageIdentifier("shared", forView: view))
		#expect(index.containsLine(receivedAt: date, nickname: "alice", messageBody: "same", forView: view))

		index.forgetLines([second.uniqueIdentifier], inView: view)
		#expect(index.containsMessageIdentifier("shared", forView: view) == false)
		#expect(index.containsLine(receivedAt: date, nickname: "alice", messageBody: "same", forView: view) == false)
		#expect(index.containsMessageIdentifier("newest", forView: view))
	}

	private func indexedView(_ line: ChatLine) -> (ScrollbackDuplicateIndex, String) {
		let index = ScrollbackDuplicateIndex()
		let view = "view-\(UUID().uuidString)"
		index.indexChatLine(line, forView: view)
		return (index, view)
	}

	@Test("The fallback match rounds to the millisecond and distinguishes nickname, body and time")
	func fallbackMatchSemantics() {
		let date = Date(timeIntervalSince1970: 1000.0004)
		let (index, view) = indexedView(chatLine(body: "hello there", messageIdentifier: "", at: date))

		#expect(index.containsLine(
			receivedAt: Date(timeIntervalSince1970: 1000.0001),
			nickname: "alice",
			messageBody: "hello there",
			forView: view
		))
		#expect(index.containsLine(receivedAt: date, nickname: "bob", messageBody: "hello there", forView: view) == false)
		#expect(index.containsLine(receivedAt: date, nickname: "alice", messageBody: "hello there!", forView: view) == false)
		#expect(index.containsLine(
			receivedAt: date.addingTimeInterval(0.002),
			nickname: "alice",
			messageBody: "hello there",
			forView: view
		) == false)
	}

	@Test("A missing nickname matches an empty one")
	func missingNicknameMatchesEmpty() {
		let date = Date(timeIntervalSince1970: 1000)
		var line = chatLine(body: "narrated", messageIdentifier: "", at: date)
		line.nickname = nil
		let (index, view) = indexedView(line)

		#expect(index.containsLine(receivedAt: date, nickname: "", messageBody: "narrated", forView: view))
		#expect(index.containsLine(receivedAt: date, nickname: nil, messageBody: "narrated", forView: view))
	}

	@Test("A nickname and body cannot be split a different way to match")
	func nicknameAndBodyBoundaryIsUnambiguous() {
		let date = Date(timeIntervalSince1970: 1000)
		var line = chatLine(body: "b\u{1f}c", messageIdentifier: "", at: date)
		line.nickname = "a"
		let (index, view) = indexedView(line)

		#expect(index.containsLine(receivedAt: date, nickname: "a", messageBody: "b\u{1f}c", forView: view))
		#expect(index.containsLine(receivedAt: date, nickname: "a\u{1f}b", messageBody: "c", forView: view) == false)
	}

	@Test("Long bodies that differ only at the end are told apart")
	func longBodiesDifferingAtTheEnd() {
		let date = Date(timeIntervalSince1970: 1000)
		let prefix = String(repeating: "x", count: 4096)
		let (index, view) = indexedView(chatLine(body: prefix + "a", messageIdentifier: "", at: date))

		#expect(index.containsLine(receivedAt: date, nickname: "alice", messageBody: prefix + "a", forView: view))
		#expect(index.containsLine(receivedAt: date, nickname: "alice", messageBody: prefix + "b", forView: view) == false)
	}
}
