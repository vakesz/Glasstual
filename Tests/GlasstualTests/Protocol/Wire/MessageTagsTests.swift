// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation
@testable import Glasstual
import Testing

/// IRCv3 typing notifications, replies, and reactions.
@MainActor
@Suite("IRCv3 message tags")
struct MessageTagsTests {
	@Test("An active typing tag is sent at most once every three seconds")
	func typingActiveIsThrottledToEveryThreeSeconds() throws {
		let session = makeMessageTagsSession()
		let channel = try addChannel(named: "#chat", to: session)
		let start = Date()

		session.typingSender.noteText("h", in: channel, at: start)
		session.typingSender.noteText("he", in: channel, at: start.addingTimeInterval(1))
		session.typingSender.noteText("hel", in: channel, at: start.addingTimeInterval(2.9))

		#expect(sentLines(of: session) == ["@+typing=active TAGMSG #chat"])

		session.typingSender.noteText("hell", in: channel, at: start.addingTimeInterval(3))

		#expect(session.sentLines.count == 2)
		#expect(sentLines(of: session).last == "@+typing=active TAGMSG #chat")
	}

	@Test("Typing pauses when the timer fires and goes active again on the next keystroke")
	func typingPausedAfterIdleThenActiveAgain() throws {
		let session = makeMessageTagsSession()
		let channel = try addChannel(named: "#chat", to: session)
		let start = Date()

		session.typingSender.noteText("h", in: channel, at: start)
		session.typingSender.pause(in: channel, at: start.addingTimeInterval(5))

		#expect(sentLines(of: session) == [
			"@+typing=active TAGMSG #chat",
			"@+typing=paused TAGMSG #chat",
		])

		session.typingSender.noteText("he", in: channel, at: start.addingTimeInterval(8))

		#expect(sentLines(of: session).last == "@+typing=active TAGMSG #chat")
		#expect(session.sentLines.count == 3)
	}

	@Test("Typing is done once the text is cleared or sent, and is not repeated")
	func typingDoneWhenTextClearedOrSent() throws {
		let session = makeMessageTagsSession()
		let channel = try addChannel(named: "#chat", to: session)
		let start = Date()

		session.typingSender.noteText("h", in: channel, at: start)
		session.typingSender.noteText("", in: channel, at: start.addingTimeInterval(3))

		#expect(sentLines(of: session) == [
			"@+typing=active TAGMSG #chat",
			"@+typing=done TAGMSG #chat",
		])

		session.typingSender.noteText("", in: channel, at: start.addingTimeInterval(4))

		#expect(session.sentLines.count == 2)

		session.typingSender.noteText("x", in: channel, at: start.addingTimeInterval(6))
		session.typingSender.finish(in: channel, at: start.addingTimeInterval(9))

		#expect(sentLines(of: session).last == "@+typing=done TAGMSG #chat")
		#expect(session.sentLines.count == 4)
	}

	@Test("A line that starts a command is not reported as typing")
	func typingIsNotSentForCommands() throws {
		let session = makeMessageTagsSession()
		let channel = try addChannel(named: "#chat", to: session)
		let start = Date()

		session.typingSender.noteText("/", in: channel, at: Date())
		session.typingSender.noteText("/me", in: channel, at: Date())

		#expect(session.sentLines.count == 0)

		session.typingSender.noteText("h", in: channel, at: start)
		session.typingSender.noteText("/h", in: channel, at: start.addingTimeInterval(3))

		#expect(sentLines(of: session) == [
			"@+typing=active TAGMSG #chat",
			"@+typing=done TAGMSG #chat",
		])
	}

	@Test("Typing needs message-tags, and the console is never a typing target")
	func typingIsNotSentWithoutMessageTagsOrToConsole() throws {
		let session = TestServerSession()
		session.markAsLoggedIn()
		let channel = try addChannel(named: "#chat", to: session)

		session.typingSender.noteText("h", in: channel, at: Date())
		session.typingSender.noteText("h", in: nil, at: Date())

		#expect(session.sentLines.count == 0)

		let tagged = makeMessageTagsSession()
		tagged.typingSender.noteText("h", in: nil, at: Date())

		#expect(tagged.sentLines.count == 0)
	}

	@Test("Nothing is sent while the typing notification preference is off")
	func typingRespectsSetting() throws {
		let session = makeMessageTagsSession()
		session.environment.settings.sendTypingNotifications = false
		let channel = try addChannel(named: "#chat", to: session)

		session.typingSender.noteText("h", in: channel, at: Date())

		#expect(session.sentLines.count == 0)
	}

	@Test("A remote typing state ages out of the tracker")
	func typingStateExpires() throws {
		let session = makeMessageTagsSession()
		let channel = try addChannel(named: "#chat", to: session)
		let tracker = session.typingTracker
		let start = Date()

		tracker.noteTypingState(.active, fromNickname: "mara", in: channel, at: start)
		tracker.noteTypingState(.paused, fromNickname: "jonas", in: channel, at: start)

		#expect(tracker.typingNicknames(in: channel, at: start.addingTimeInterval(5)) == ["mara", "jonas"])
		#expect(tracker.typingNicknames(in: channel, at: start.addingTimeInterval(7)) == ["jonas"])
		#expect(tracker.typingNicknames(in: channel, at: start.addingTimeInterval(31)) == [])

		tracker.expireEntries(at: start.addingTimeInterval(31))

		#expect(tracker.typingNicknames(in: channel, at: start) == [])
	}

	@Test("A received TAGMSG feeds the tracker, and the local user is never tracked")
	func typingDoneRemovesEntryAndTagMessageFeedsTracker() throws {
		let session = makeMessageTagsSession()
		let channel = try addChannel(named: "#chat", to: session)
		let tracker = session.typingTracker

		try session.receiveTagMessage(message("@+typing=active :mara!u@h TAGMSG #chat", on: session))

		#expect(tracker.typingNicknames(in: channel) == ["mara"])

		try session.receiveTagMessage(message("@+typing=done :mara!u@h TAGMSG #chat", on: session))

		#expect(tracker.typingNicknames(in: channel) == [])

		try session.receiveTagMessage(message("@+typing=active :me!u@h TAGMSG #chat", on: session))

		#expect(tracker.typingNicknames(in: channel) == [])
	}

	@Test("A reply tag rides the first line of a multi-line message only")
	func replyTagIsSentOnFirstLineOnly() throws {
		let session = makeMessageTagsSession()
		let channel = try addChannel(named: "#chat", to: session)
		session.nextMessageReplyIdentifier = "abc123"

		session.sendText(NSAttributedString(string: "first\nsecond"), as: .privmsg, to: channel)

		let privateMessages = sentLines(of: session).filter { $0.contains("PRIVMSG") }

		#expect(privateMessages == [
			"@+draft/reply=abc123 PRIVMSG #chat :first",
			"PRIVMSG #chat :second",
		])
		#expect(session.nextMessageReplyIdentifier == nil)

		let firstPrinted = session.printedLines.firstObject as? [String: Any]

		#expect(firstPrinted?["messageBody"] as? String == "first")

		session.sendText(NSAttributedString(string: "third"), as: .privmsg, to: channel)

		#expect(sentLines(of: session).last == "PRIVMSG #chat :third")
	}

	@Test("Queued input keeps its own reply tag across a capacity wait")
	func queuedInputKeepsItsOwnReply() async throws {
		let session = makeMessageTagsSession()
		let channel = try addChannel(named: "#chat", to: session)
		let admission = RenderAdmission(capacity: 1)
		session.renderAdmission = admission
		let ticket = admission.submit(for: "existing")
		defer { session.cancelPendingSessionTasks(); admission.finish(ticket) }
		session.nextMessageReplyIdentifier = "first-reply"
		session.inputText("first", destination: channel)
		session.nextMessageReplyIdentifier = "second-reply"
		session.inputText("second", destination: channel)
		#expect(sentLines(of: session).isEmpty)
		admission.finish(ticket)
		let deadline = ContinuousClock.now + .seconds(5)
		while session.outboundTextProducer?.pendingProducerCount != 0, ContinuousClock.now < deadline {
			await Task.yield()
		}
		#expect(sentLines(of: session) == [
			"@+draft/reply=first-reply PRIVMSG #chat :first",
			"@+draft/reply=second-reply PRIVMSG #chat :second",
		])
		#expect(session.nextMessageReplyIdentifier == nil)
	}

	@Test("Without message-tags the reply tag is dropped from the wire")
	func replyTagIsDroppedWithoutMessageTags() throws {
		let session = TestServerSession()
		session.markAsLoggedIn()
		let channel = try addChannel(named: "#chat", to: session)
		session.nextMessageReplyIdentifier = "abc123"

		session.sendText(NSAttributedString(string: "hello"), as: .privmsg, to: channel)

		#expect(sentLines(of: session).last == "PRIVMSG #chat :hello")
	}

	@Test("A reaction is sent as a TAGMSG carrying the react and reply tags")
	func reactionSendsTagMessage() throws {
		let session = makeMessageTagsSession()
		let channel = try addChannel(named: "#chat", to: session)

		#expect(session.sendReaction("👍", toMessageIdentifier: "abc123", in: channel))
		#expect(sentLines(of: session) == ["@+draft/react=👍;+draft/reply=abc123 TAGMSG #chat"])
	}

	@Test("A reaction is refused when the server has no message-tags")
	func reactionRequiresMessageTags() throws {
		let session = TestServerSession()
		session.markAsLoggedIn()
		let channel = try addChannel(named: "#chat", to: session)

		#expect(session.sendReaction("👍", toMessageIdentifier: "abc123", in: channel) == false)
		#expect(session.sentLines.count == 0)
	}

	private func makeMessageTagsSession() -> TestServerSession {
		let session = TestServerSession(configDictionary: ["nickname": "me", "username": "me"])
		session.environment.settings.sendTypingNotifications = true
		session.enableCapability(.messageTags)
		session.markAsLoggedIn()

		return session
	}

	private func addChannel(named name: String, to session: TestServerSession) throws -> Conversation {
		let channel = try #require(session.findConversationOrCreate(name))

		channel.activate()

		return channel
	}

	private func message(_ line: String, on session: ServerSession) throws -> Message {
		try #require(Message(line: line, on: session))
	}

	private func sentLines(of session: TestServerSession) -> [String] {
		(session.sentLines as NSArray).compactMap { $0 as? String }
	}
}
