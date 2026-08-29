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

/// IRCv3 typing notifications, replies, and reactions.
@MainActor
@Suite("IRCv3 message tags", .serialized)
final class IRCMessageTagsTests {
	private nonisolated static let typingPreferenceKey = "SendTypingNotifications"
	private let originalTypingPreference: Bool?

	init() {
		let defaults = TextualUserDefaults.container
		originalTypingPreference = defaults
			.persistentDomain(forName: ApplicationGroup.identifier)?[Self.typingPreferenceKey] as? Bool
		defaults.set(true, forKey: Self.typingPreferenceKey)
	}

	deinit {
		let defaults = TextualUserDefaults.container
		if let originalTypingPreference {
			defaults.set(originalTypingPreference, forKey: Self.typingPreferenceKey)
		} else {
			defaults.removeObject(forKey: Self.typingPreferenceKey)
		}
	}

	@Test("An active typing tag is sent at most once every three seconds")
	func typingActiveIsThrottledToEveryThreeSeconds() throws {
		let client = makeMessageTagsClient()
		let channel = try addChannel(named: "#chat", to: client)
		let start = Date()

		client.noteLocalUserTyping("h", in: channel, at: start)
		client.noteLocalUserTyping("he", in: channel, at: start.addingTimeInterval(1))
		client.noteLocalUserTyping("hel", in: channel, at: start.addingTimeInterval(2.9))

		#expect(sentLines(of: client) == ["@+typing=active TAGMSG #chat"])

		client.noteLocalUserTyping("hell", in: channel, at: start.addingTimeInterval(3))

		#expect(client.sentLines.count == 2)
		#expect(sentLines(of: client).last == "@+typing=active TAGMSG #chat")
	}

	@Test("Typing pauses when the timer fires and goes active again on the next keystroke")
	func typingPausedAfterIdleThenActiveAgain() throws {
		let client = makeMessageTagsClient()
		let channel = try addChannel(named: "#chat", to: client)
		let start = Date()

		client.noteLocalUserTyping("h", in: channel, at: start)
		client.typingPauseTimerFired(channel)

		#expect(sentLines(of: client) == [
			"@+typing=active TAGMSG #chat",
			"@+typing=paused TAGMSG #chat",
		])

		client.noteLocalUserTyping("he", in: channel, at: start.addingTimeInterval(0.5))

		#expect(sentLines(of: client).last == "@+typing=active TAGMSG #chat")
		#expect(client.sentLines.count == 3)
	}

	@Test("Typing is done once the text is cleared or sent, and is not repeated")
	func typingDoneWhenTextClearedOrSent() throws {
		let client = makeMessageTagsClient()
		let channel = try addChannel(named: "#chat", to: client)

		client.noteLocalUserTyping("h", in: channel, at: Date())
		client.noteLocalUserTyping("", in: channel, at: Date())

		#expect(sentLines(of: client) == [
			"@+typing=active TAGMSG #chat",
			"@+typing=done TAGMSG #chat",
		])

		client.noteLocalUserTyping("", in: channel, at: Date())

		#expect(client.sentLines.count == 2)

		client.noteLocalUserTyping("x", in: channel, at: Date())
		client.localUserSentMessage(in: channel)

		#expect(sentLines(of: client).last == "@+typing=done TAGMSG #chat")
		#expect(client.sentLines.count == 4)
	}

	@Test("A line that starts a command is not reported as typing")
	func typingIsNotSentForCommands() throws {
		let client = makeMessageTagsClient()
		let channel = try addChannel(named: "#chat", to: client)

		client.noteLocalUserTyping("/", in: channel, at: Date())
		client.noteLocalUserTyping("/me", in: channel, at: Date())

		#expect(client.sentLines.count == 0)

		client.noteLocalUserTyping("h", in: channel, at: Date())
		client.noteLocalUserTyping("/h", in: channel, at: Date())

		#expect(sentLines(of: client) == [
			"@+typing=active TAGMSG #chat",
			"@+typing=done TAGMSG #chat",
		])
	}

	@Test("Typing needs message-tags, and the console is never a typing target")
	func typingIsNotSentWithoutMessageTagsOrToConsole() throws {
		let client = GLTTestClient()
		client.markAsLoggedIn()
		let channel = try addChannel(named: "#chat", to: client)

		client.noteLocalUserTyping("h", in: channel, at: Date())
		client.noteLocalUserTyping("h", in: nil, at: Date())

		#expect(client.sentLines.count == 0)

		let tagged = makeMessageTagsClient()
		tagged.noteLocalUserTyping("h", in: nil, at: Date())

		#expect(tagged.sentLines.count == 0)
	}

	@Test("Nothing is sent while the typing notification preference is off")
	func typingRespectsPreference() throws {
		TextualUserDefaults.container.set(false, forKey: Self.typingPreferenceKey)
		let client = makeMessageTagsClient()
		let channel = try addChannel(named: "#chat", to: client)

		client.noteLocalUserTyping("h", in: channel, at: Date())

		#expect(client.sentLines.count == 0)
	}

	@Test("A remote typing state ages out of the tracker")
	func typingStateExpires() throws {
		let client = makeMessageTagsClient()
		let channel = try addChannel(named: "#chat", to: client)
		let tracker = try #require(client.typingTracker)
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
		let client = makeMessageTagsClient()
		let channel = try addChannel(named: "#chat", to: client)
		let tracker = try #require(client.typingTracker)

		try client.receiveTagMessage(message("@+typing=active :mara!u@h TAGMSG #chat", on: client))

		#expect(tracker.typingNicknames(in: channel) == ["mara"])

		try client.receiveTagMessage(message("@+typing=done :mara!u@h TAGMSG #chat", on: client))

		#expect(tracker.typingNicknames(in: channel) == [])

		try client.receiveTagMessage(message("@+typing=active :me!u@h TAGMSG #chat", on: client))

		#expect(tracker.typingNicknames(in: channel) == [])
	}

	@Test("A reply tag rides the first line of a multi-line message only")
	func replyTagIsSentOnFirstLineOnly() throws {
		let client = makeMessageTagsClient()
		let channel = try addChannel(named: "#chat", to: client)
		client.nextMessageReplyIdentifier = "abc123"

		client.sendText(NSAttributedString(string: "first\nsecond"), as: .privmsg, to: channel)

		let privateMessages = sentLines(of: client).filter { $0.contains("PRIVMSG") }

		#expect(privateMessages == [
			"@+draft/reply=abc123 PRIVMSG #chat :first",
			"PRIVMSG #chat :second",
		])
		#expect(client.nextMessageReplyIdentifier == nil)

		let firstPrinted = client.printedLines.firstObject as? [String: Any]

		#expect(firstPrinted?["messageBody"] as? String == "first")

		client.sendText(NSAttributedString(string: "third"), as: .privmsg, to: channel)

		#expect(sentLines(of: client).last == "PRIVMSG #chat :third")
	}

	@Test("Without message-tags the reply tag is dropped from the wire")
	func replyTagIsDroppedWithoutMessageTags() throws {
		let client = GLTTestClient()
		client.markAsLoggedIn()
		let channel = try addChannel(named: "#chat", to: client)
		client.nextMessageReplyIdentifier = "abc123"

		client.sendText(NSAttributedString(string: "hello"), as: .privmsg, to: channel)

		#expect(sentLines(of: client).last == "PRIVMSG #chat :hello")
	}

	@Test("A reaction is sent as a TAGMSG carrying the react and reply tags")
	func reactionSendsTagMessage() throws {
		let client = makeMessageTagsClient()
		let channel = try addChannel(named: "#chat", to: client)

		#expect(client.sendReaction("👍", toMessageIdentifier: "abc123", in: channel))
		#expect(sentLines(of: client) == ["@+draft/react=👍;+draft/reply=abc123 TAGMSG #chat"])
	}

	@Test("A reaction is refused when the server has no message-tags")
	func reactionRequiresMessageTags() throws {
		let client = GLTTestClient()
		client.markAsLoggedIn()
		let channel = try addChannel(named: "#chat", to: client)

		#expect(client.sendReaction("👍", toMessageIdentifier: "abc123", in: channel) == false)
		#expect(client.sentLines.count == 0)
	}

	@Test("The TAGMSG event carries the sender, the tags and who sent it")
	func tagMessageEventShape() {
		let client = makeMessageTagsClient()
		let date = Date(timeIntervalSince1970: 1_700_000_000)
		let tags = ["draft/react": "👍", "draft/reply": "abc123"]
		let event = client.tagMessageEvent(
			withClientTags: tags,
			sender: "mara",
			target: "#chat",
			timestamp: date,
			messageIdentifier: "tag1",
			account: "mara"
		)
		let expected: NSDictionary = [
			"sender": "mara",
			"target": "#chat",
			"tags": tags,
			"timestamp": 1_700_000_000.0,
			"fromLocalUser": false,
			"localUserNickname": "me",
			"msgid": "tag1",
			"account": "mara",
		]

		#expect(event as NSDictionary == expected)

		let own = client.tagMessageEvent(
			withClientTags: tags,
			sender: "me",
			target: "#chat",
			timestamp: date,
			messageIdentifier: nil,
			account: nil
		)

		#expect(own["fromLocalUser"] as? Bool == true)
		#expect(own["msgid"] == nil)
		#expect(own["account"] == nil)
	}

	private func makeMessageTagsClient() -> GLTTestClient {
		let configuration: NSDictionary = [
			"nickname": "me",
			"username": "me",
		]
		guard let configuration = configuration as? [String: Any] else {
			preconditionFailure("Test configuration must bridge to a Swift dictionary")
		}
		let client = GLTTestClient(configDictionary: configuration)

		client.enableCapability(.messageTags)
		client.markAsLoggedIn()

		return client
	}

	private func addChannel(named name: String, to client: GLTTestClient) throws -> Channel {
		let channel = try #require(client.findChannelOrCreate(name))

		channel.activate()

		return channel
	}

	private func message(_ line: String, on client: IRCClient) throws -> Message {
		try #require(Message(line: line, on: client))
	}

	private func sentLines(of client: GLTTestClient) -> [String] {
		(client.sentLines as NSArray).compactMap { $0 as? String }
	}
}
