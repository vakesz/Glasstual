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
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 *
 *  * Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 *  * Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 *  * Neither the name of Textual, "Codeux Software, LLC", nor the
 *    names of its contributors may be used to endorse or promote products
 *    derived from this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED. IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
 * FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
 * OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
 * LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
 * OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
 * SUCH DAMAGE.
 *
 *********************************************************************** */

import Foundation
@testable import Glasstual
import Testing

/** What makes an inbound line replay rather than a live one.

 Every message on a network that offers `server-time` carries the tag, so the
 tag alone cannot mean "this already happened": reading it that way marked
 every live line historic and left the typing indicator permanently silent. */
@MainActor
struct IRCMessageHistoricRuleTests {
	private func historicRuleClient() -> GLTTestClient {
		let client = GLTTestClient(configDictionary: ["nickname": "me", "username": "me"])

		client.enableCapability(.serverTime)
		client.enableCapability(.batch)
		client.markAsLoggedIn()

		return client
	}

	private func timestamp(_ date: Date) -> String {
		let formatter = ISO8601DateFormatter()

		formatter.formatOptions = [.withInternetDateTime]
		formatter.timeZone = TimeZone(abbreviation: "UTC")

		return formatter.string(from: date)
	}

	@discardableResult
	private func openBatch(_ token: String, type: String, on client: GLTTestClient) -> MessageBatch {
		let batch = MessageBatch()

		batch.batchToken = token
		batch.batchType = type
		batch.batchIsOpen = true
		client.batchMessages.queueEntry(batch)

		return batch
	}

	@Test("A live message carrying server-time is not historic")
	func liveServerTimeIsNotHistoric() throws {
		let client = historicRuleClient()
		let line = "@time=\(timestamp(Date())) :mara!u@h PRIVMSG #chat :hi"
		let message = try #require(Message(line: line, on: client))

		#expect(message.isHistoric == false)
		#expect(message.hasServerTime)
	}

	@Test(
		"A server-time further behind the clock than the tolerance is replay",
		arguments: [-31.0, -3600.0, -86400.0]
	)
	func staleServerTimeIsHistoric(_ offset: TimeInterval) throws {
		let client = historicRuleClient()
		let stamp = timestamp(Date().addingTimeInterval(offset))
		let message = try #require(Message(line: "@time=\(stamp) :mara!u@h PRIVMSG #chat :hi", on: client))

		#expect(message.isHistoric)
	}

	/// Clock skew between the server and this Mac is common and is not replay,
	/// so a stamp inside the tolerance — in either direction — stays live.
	@Test("A stamp a few seconds either side of the clock is still live", arguments: [-29.0, -5.0, 5.0, 60.0])
	func smallClockSkewIsStillLive(_ offset: TimeInterval) throws {
		let client = historicRuleClient()
		let stamp = timestamp(Date().addingTimeInterval(offset))
		let message = try #require(Message(line: "@time=\(stamp) :mara!u@h PRIVMSG #chat :hi", on: client))

		#expect(message.isHistoric == false)
	}

	/// A `chathistory` batch says outright that it replays, so its contents are
	/// historic no matter how fresh the stamps are — a `CHATHISTORY LATEST`
	/// request answers with lines said seconds ago.
	@Test("Anything inside a chathistory batch is historic", arguments: ["chathistory", "draft/chathistory"])
	func chatHistoryBatchIsHistoric(_ type: String) throws {
		let client = historicRuleClient()

		openBatch("h1", type: type, on: client)

		let line = "@batch=h1;time=\(timestamp(Date())) :mara!u@h PRIVMSG #chat :hi"
		let message = try #require(Message(line: line, on: client))

		#expect(message.isHistoric)
	}

	@Test("A ZNC playback batch is historic even when its stamps are fresh")
	func playbackBatchIsHistoric() throws {
		let client = historicRuleClient()

		openBatch("p1", type: "znc.in/playback", on: client)

		let line = "@batch=p1;time=\(timestamp(Date())) :mara!u@h PRIVMSG #chat :hi"
		let message = try #require(Message(line: line, on: client))

		#expect(message.isHistoric)
	}

	/// The replay verdict follows the whole chain, so a `netsplit` batch nested
	/// inside a replay is replay too.
	@Test("A batch nested inside a replay batch is historic")
	func nestedBatchInheritsReplay() throws {
		let client = historicRuleClient()
		let outer = openBatch("h1", type: "chathistory", on: client)
		let inner = openBatch("n1", type: "netsplit", on: client)

		inner.parentBatchMessage = outer

		let line = "@batch=n1;time=\(timestamp(Date())) :mara!u@h PRIVMSG #chat :hi"
		let message = try #require(Message(line: line, on: client))

		#expect(message.isHistoric)
	}

	/// A batch that is not replay adds nothing: freshness alone decides.
	@Test("A live batch leaves a fresh message live")
	func liveBatchStaysLive() throws {
		let client = historicRuleClient()

		openBatch("n1", type: "netsplit", on: client)

		let line = "@batch=n1;time=\(timestamp(Date())) :mara!u@h PRIVMSG #chat :hi"
		let message = try #require(Message(line: line, on: client))

		#expect(message.isHistoric == false)
	}

	/// The whole point of the rule: a TAGMSG that arrives live with a
	/// `server-time` tag has to reach the typing tracker.
	@Test("A live TAGMSG carrying server-time still updates the typing tracker")
	func liveTagMessageUpdatesTheTypingTracker() throws {
		let client = historicRuleClient()
		let channel = try #require(client.findChannelOrCreate("#chat"))

		channel.activate()

		let tracker = try #require(client.typingTracker)
		let line = "@+typing=active;time=\(timestamp(Date())) :mara!u@h TAGMSG #chat"

		try client.receiveTagMessage(#require(Message(line: line, on: client)))

		#expect(tracker.typingNicknames(in: channel) == ["mara"])
	}

	/// Replay must not resurrect an indicator for someone who stopped typing
	/// hours ago.
	@Test("A replayed TAGMSG leaves the typing tracker alone")
	func replayedTagMessageIsIgnored() throws {
		let client = historicRuleClient()
		let channel = try #require(client.findChannelOrCreate("#chat"))

		channel.activate()

		openBatch("h1", type: "chathistory", on: client)

		let tracker = try #require(client.typingTracker)
		let line = "@batch=h1;+typing=active;time=\(timestamp(Date())) :mara!u@h TAGMSG #chat"

		try client.receiveTagMessage(#require(Message(line: line, on: client)))

		#expect(tracker.typingNicknames(in: channel) == [])
	}

	/// The bouncer resume point tracks the newest stamp seen, live or replayed,
	/// because that is where a reconnect asks playback to start.
	@Test("A live stamped message still advances the stored server time")
	func liveMessageAdvancesTheStoredServerTime() throws {
		let client = historicRuleClient()
		let sentAt = Date()
		let line = "@time=\(timestamp(sentAt)) :mara!u@h PRIVMSG #chat :hi"

		client.forwardsProcessedMessages = true

		try client.processIncomingMessage(#require(Message(line: line, on: client)))

		#expect(abs(client.lastMessageServerTime - sentAt.timeIntervalSince1970) < 1)
	}
}
