// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing

/** What makes an inbound line replay rather than a live one.

 Every message on a network that offers `server-time` carries the tag, so the
 tag alone cannot mean "this already happened": reading it that way marked
 every live line replayed and left the typing indicator permanently silent. */
@MainActor
struct MessageReplayRuleTests {
	private func replayRuleSession() -> TestServerSession {
		let session = TestServerSession(configDictionary: ["nickname": "me", "username": "me"])

		session.enableCapability(.serverTime)
		session.enableCapability(.batch)
		session.markAsLoggedIn()

		return session
	}

	private func timestamp(_ date: Date) -> String {
		let formatter = ISO8601DateFormatter()

		formatter.formatOptions = [.withInternetDateTime]
		formatter.timeZone = TimeZone(abbreviation: "UTC")

		return formatter.string(from: date)
	}

	@discardableResult
	private func openBatch(_ token: String, type: String, on session: TestServerSession) -> MessageBatch {
		let batch = MessageBatch()

		batch.batchToken = token
		batch.batchType = type
		batch.batchIsOpen = true
		session.batchMessages.queueEntry(batch)

		return batch
	}

	@Test("Clock skew on an ordinary server does not classify live traffic as playback")
	func clockSkewIsNotPlayback() throws {
		let session = replayRuleSession()
		let stamp = DateFormatting.iso8601String(from: Date().addingTimeInterval(-120))
		let message = try #require(Message(line: "@time=\(stamp) :bob!u@h PRIVMSG #chat :live", on: session))
		#expect(!message.isReplayed)
	}

	@Test(
		"A server-time further behind the clock than the tolerance is replay",
		arguments: [-31.0, -3600.0, -86400.0]
	)
	func staleServerTimeIsReplayed(_ offset: TimeInterval) throws {
		let session = replayRuleSession()
		session.znc.isConnected = true
		let stamp = timestamp(Date().addingTimeInterval(offset))
		let message = try #require(Message(line: "@time=\(stamp) :mara!u@h PRIVMSG #chat :hi", on: session))

		#expect(message.isReplayed)
	}

	/// Clock skew between the server and this Mac is common and is not replay,
	/// so a stamp inside the tolerance — in either direction — stays live.
	@Test("A stamp a few seconds either side of the clock is still live", arguments: [-29.0, -5.0, 5.0, 60.0])
	func smallClockSkewIsStillLive(_ offset: TimeInterval) throws {
		let session = replayRuleSession()
		let stamp = timestamp(Date().addingTimeInterval(offset))
		let message = try #require(Message(line: "@time=\(stamp) :mara!u@h PRIVMSG #chat :hi", on: session))

		#expect(message.isReplayed == false)
	}

	/// A `chathistory` batch says outright that it replays, so its contents are
	/// replayed no matter how fresh the stamps are — a `CHATHISTORY LATEST`
	/// request answers with lines said seconds ago.
	@Test("Anything inside a chathistory batch is replayed", arguments: ["chathistory", "draft/chathistory"])
	func chatHistoryBatchIsReplayed(_ type: String) throws {
		let session = replayRuleSession()

		openBatch("h1", type: type, on: session)

		let line = "@batch=h1;time=\(timestamp(Date())) :mara!u@h PRIVMSG #chat :hi"
		let message = try #require(Message(line: line, on: session))

		#expect(message.isReplayed)
	}

	@Test("A ZNC playback batch is replayed even when its stamps are fresh")
	func playbackBatchIsReplayed() throws {
		let session = replayRuleSession()

		openBatch("p1", type: "znc.in/playback", on: session)

		let line = "@batch=p1;time=\(timestamp(Date())) :mara!u@h PRIVMSG #chat :hi"
		let message = try #require(Message(line: line, on: session))

		#expect(message.isReplayed)
	}

	/// The replay verdict follows the whole chain, so a `netsplit` batch nested
	/// inside a replay is replay too.
	@Test("A batch nested inside a replay batch is replayed")
	func nestedBatchInheritsReplay() throws {
		let session = replayRuleSession()
		let outer = openBatch("h1", type: "chathistory", on: session)
		let inner = openBatch("n1", type: "netsplit", on: session)

		inner.parentBatchMessage = outer

		let line = "@batch=n1;time=\(timestamp(Date())) :mara!u@h PRIVMSG #chat :hi"
		let message = try #require(Message(line: line, on: session))

		#expect(message.isReplayed)
	}

	/// A batch that is not replay adds nothing: freshness alone decides.
	@Test("A live batch leaves a fresh message live")
	func liveBatchStaysLive() throws {
		let session = replayRuleSession()

		openBatch("n1", type: "netsplit", on: session)

		let line = "@batch=n1;time=\(timestamp(Date())) :mara!u@h PRIVMSG #chat :hi"
		let message = try #require(Message(line: line, on: session))

		#expect(message.isReplayed == false)
	}

	/// The whole point of the rule: a TAGMSG that arrives live with a
	/// `server-time` tag has to reach the typing tracker.
	@Test("A live TAGMSG carrying server-time still updates the typing tracker")
	func liveTagMessageUpdatesTheTypingTracker() throws {
		let session = replayRuleSession()
		let channel = try #require(session.findConversationOrCreate("#chat"))

		channel.activate()

		let tracker = session.typingTracker
		let line = "@+typing=active;time=\(timestamp(Date())) :mara!u@h TAGMSG #chat"

		try session.receiveTagMessage(#require(Message(line: line, on: session)))

		#expect(tracker.typingNicknames(in: channel) == ["mara"])
	}

	/// Replay must not resurrect an indicator for someone who stopped typing
	/// hours ago.
	@Test("A replayed TAGMSG leaves the typing tracker alone")
	func replayedTagMessageIsIgnored() throws {
		let session = replayRuleSession()
		let channel = try #require(session.findConversationOrCreate("#chat"))

		channel.activate()

		openBatch("h1", type: "chathistory", on: session)

		let tracker = session.typingTracker
		let line = "@batch=h1;+typing=active;time=\(timestamp(Date())) :mara!u@h TAGMSG #chat"

		try session.receiveTagMessage(#require(Message(line: line, on: session)))

		#expect(tracker.typingNicknames(in: channel) == [])
	}

	/// The bouncer resume point tracks the newest stamp seen, live or replayed,
	/// because that is where a reconnect asks playback to start.
	@Test("A live stamped message still advances the stored server time")
	func liveMessageAdvancesTheStoredServerTime() throws {
		let session = replayRuleSession()
		let sentAt = Date()
		let line = "@time=\(timestamp(sentAt)) :mara!u@h PRIVMSG #chat :hi"

		session.forwardsProcessedMessages = true

		try session.processIncomingMessage(#require(Message(line: line, on: session)))

		#expect(abs(session.lastMessageServerTime - sentAt.timeIntervalSince1970) < 1)
	}

	/** A `@time` tag is server-controlled text, so the parser reads only what
	 can be a Unix time in seconds. Anything else leaves the message with no
	 server time and its own arrival stamp, which stays inside the range every
	 later narrowing holds — the resume point the reconnect sends, and the line
	 numbers the transcript stores. */
	@Test(
		"A Unix stamp that cannot be a time is ignored",
		arguments: [
			String(repeating: "9", count: 40),
			"1e400",
			"inf",
			"nan",
			"100000000000.1",
			"",
			".",
		]
	)
	func implausibleUnixStampIsIgnored(_ tag: String) throws {
		let session = replayRuleSession()
		let message = try #require(Message(line: "@time=\(tag) :mara!u@h PRIVMSG #chat :hi", on: session))

		#expect(message.hasServerTime == false)
		#expect(message.isReplayed == false)
		#expect(message.receivedAt.timeIntervalSince1970.isFinite)
		#expect(Int64(exactly: message.receivedAt.timeIntervalSince1970.rounded()) != nil)
	}

	/// The ceiling only rejects what cannot be a Unix time in seconds, which is
	/// how the tag has always been read.
	@Test("A plausible Unix stamp is still read", arguments: [1_700_000_000.0, 946_684_800.0])
	func plausibleUnixStampIsRead(_ seconds: TimeInterval) throws {
		let session = replayRuleSession()
		let message = try #require(Message(
			line: "@time=\(Int(seconds)) :mara!u@h PRIVMSG #chat :hi",
			on: session
		))

		#expect(message.hasServerTime)
		#expect(message.receivedAt.timeIntervalSince1970 == seconds)
	}
}
