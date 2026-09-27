// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Synchronization
import Testing

@MainActor
@Suite("Typing tracker")
struct TypingTrackerTests {
	private let session: TestServerSession
	private let tracker: TypingTracker

	init() {
		let session = TestServerSession()

		self.session = session
		tracker = TypingTracker(session: session)
	}

	@Test("A tag value only names a state when it is spelled exactly")
	func stateParsing() {
		#expect(TypingTracker.state(forTagValue: "active") == .active)
		#expect(TypingTracker.state(forTagValue: "paused") == .paused)
		#expect(TypingTracker.state(forTagValue: "ACTIVE") == .done)
		#expect(TypingTracker.state(forTagValue: "done") == .done)
		#expect(TypingTracker.state(forTagValue: nil) == .done)
	}

	@Test("Nicknames keep their first spelling and their arrival order, and a repeat is not announced")
	func orderingCaseFoldingAndNotificationSuppression() {
		let channel = makeChannel(named: "#chat")
		let start = Date(timeIntervalSince1970: 1000)
		let notificationCount = Mutex(0)
		let notifiedChannel = Mutex<Conversation?>(nil)
		let token = NotificationCenter.default.addObserver(
			forName: .typingTrackerDidChange,
			object: session,
			queue: nil
		) { notification in
			notificationCount.withLock { count in
				count += 1
			}
			notifiedChannel.withLock { notifiedChannel in
				notifiedChannel = notification.userInfo?[typingTrackerConversationKey] as? Conversation
			}
		}
		defer { NotificationCenter.default.removeObserver(token) }

		tracker.noteTypingState(.active, fromNickname: "Alice", in: channel, at: start)
		tracker.noteTypingState(.active, fromNickname: "bob", in: channel, at: start.addingTimeInterval(1))
		tracker.noteTypingState(.paused, fromNickname: "ALICE", in: channel, at: start.addingTimeInterval(2))
		tracker.noteTypingState(.paused, fromNickname: "alice", in: channel, at: start.addingTimeInterval(3))

		#expect(tracker.typingNicknames(in: channel, at: start.addingTimeInterval(4)) == ["Alice", "bob"])
		#expect(notificationCount.withLock { $0 } == 3)
		#expect(notifiedChannel.withLock { $0 === channel })
	}

	@Test("A state with no nickname is dropped without announcing anything")
	func emptyNicknameIsIgnored() {
		let channel = makeChannel(named: "#chat")
		let notificationCount = Mutex(0)
		let token = NotificationCenter.default.addObserver(
			forName: .typingTrackerDidChange,
			object: session,
			queue: nil
		) { _ in
			notificationCount.withLock { count in
				count += 1
			}
		}
		defer { NotificationCenter.default.removeObserver(token) }

		tracker.noteTypingState(.active, fromNickname: "", in: channel)

		#expect(tracker.typingNicknames(in: channel) == [])
		#expect(notificationCount.withLock { $0 } == 0)
	}

	@Test("Removing a nickname removes it from every channel, whatever case it was seen in")
	func removeNicknameAcrossChannels() {
		let firstChannel = makeChannel(named: "#one")
		let secondChannel = makeChannel(named: "#two")
		let start = Date()

		tracker.noteTypingState(.active, fromNickname: "Mara", in: firstChannel, at: start)
		tracker.noteTypingState(.paused, fromNickname: "mara", in: secondChannel, at: start)
		tracker.removeNickname("MARA")

		#expect(tracker.typingNicknames(in: firstChannel, at: start) == [])
		#expect(tracker.typingNicknames(in: secondChannel, at: start) == [])
	}

	@Test("An active entry expires before a paused one, and neither expires early")
	func timeoutBoundaryAndExplicitExpiry() {
		let channel = makeChannel(named: "#chat")
		let start = Date(timeIntervalSince1970: 1000)

		tracker.noteTypingState(.active, fromNickname: "active", in: channel, at: start)
		tracker.noteTypingState(.paused, fromNickname: "paused", in: channel, at: start)

		#expect(
			tracker.typingNicknames(in: channel, at: start.addingTimeInterval(6)) == ["active", "paused"]
		)

		tracker.expireEntries(at: start.addingTimeInterval(6.001))

		#expect(tracker.typingNicknames(in: channel, at: start.addingTimeInterval(30)) == ["paused"])

		tracker.expireEntries(at: start.addingTimeInterval(30.001))

		#expect(tracker.typingNicknames(in: channel, at: start) == [])
	}

	private func makeChannel(named name: String) -> Conversation {
		let channel = Conversation(config: ConversationConfig(name: name))

		channel.associatedSession = session

		return channel
	}
}

@MainActor
@Suite("Typing state follows received messages and membership")
struct TypingReceiptTests {
	private struct Fixture {
		let session: TestServerSession
		let first: Conversation
		let second: Conversation

		init() throws {
			let session = TestServerSession(configDictionary: ["nickname": "me"])
			session.enableCapability(.messageTags)
			let first = try #require(session.findConversationOrCreate("#one"))
			let second = try #require(session.findConversationOrCreate("#two"))
			let alice = session.findUserOrCreate("Alice")
			for conversation in [first, second] {
				conversation.addUser(alice)
				session.typingTracker.noteTypingState(.paused, fromNickname: "Alice", in: conversation)
			}
			self.session = session
			self.first = first
			self.second = second
		}
	}

	@Test("A live message clears only its target's indicator", arguments: [
		"PRIVMSG #one :hello", "NOTICE #one :hello", "TAGMSG #one",
	], [true, false])
	func receivingMessage(_ command: String, _ replayed: Bool) throws {
		let fixture = try Fixture()
		let session = fixture.session
		defer { session.typingTracker.removeAll() }
		var message = try #require(Message(line: ":Alice!u@h \(command)", on: session))
		message.isReplayed = replayed
		session.processIncomingMessageOnMainActor(message)
		#expect(session.typingTracker.typingNicknames(in: fixture.first) == (replayed ? ["Alice"] : []))
		#expect(session.typingTracker.typingNicknames(in: fixture.second) == ["Alice"])
	}

	@Test("Departures clear the affected scope and nick changes retire the old name", arguments: [
		":Alice!u@h PART #one :left", ":operator!u@h KICK #one Alice :left",
		":Alice!u@h QUIT :left", ":Alice!u@h QUIT", ":Alice!u@h NICK Alicia",
		":server KILL Alice :left",
	], [true, false])
	func membershipChange(_ line: String, _ printOnly: Bool) throws {
		let fixture = try Fixture()
		let session = fixture.session
		defer { session.typingTracker.removeAll() }
		var message = try #require(Message(line: line, on: session))
		message.isPrintOnlyMessage = printOnly
		session.processIncomingMessageOnMainActor(message)
		let affectsAll = message.remoteCommand == .quit || message.remoteCommand == .nick || message.remoteCommand == .kill
		#expect(session.typingTracker.typingNicknames(in: fixture.first) == (printOnly ? ["Alice"] : []))
		#expect(session.typingTracker.typingNicknames(in: fixture.second) == (!printOnly && affectsAll ? [] : ["Alice"]))
	}

	@Test("Leaving a conversation clears every remaining typing indicator")
	func ownDepartureClearsConversation() throws {
		let fixture = try Fixture()
		let session = fixture.session
		defer { session.typingTracker.removeAll() }
		fixture.first.deactivate()
		#expect(session.typingTracker.typingNicknames(in: fixture.first).isEmpty)
		#expect(session.typingTracker.typingNicknames(in: fixture.second) == ["Alice"])
	}
}
