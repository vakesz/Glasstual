/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \\ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\\__|\__,_|\__,_|_|
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

@testable import Glasstual
import XCTest

/// IRCv3 typing notifications, replies, and reactions.
@MainActor
final class IRCMessageTagsTests: XCTestCase {
	override func setUp() {
		super.setUp()

		TextualUserDefaults.shared().set(true, forKey: "SendTypingNotifications")
	}

	override func tearDown() {
		TextualUserDefaults.shared().set(true, forKey: "SendTypingNotifications")

		super.tearDown()
	}

	func testTypingActiveIsThrottledToEveryThreeSeconds() {
		let client = makeMessageTagsClient()
		let channel = addChannel(named: "#chat", to: client)
		let start = Date()

		client.noteLocalUserTyping("h", in: channel, at: start)
		client.noteLocalUserTyping("he", in: channel, at: start.addingTimeInterval(1))
		client.noteLocalUserTyping("hel", in: channel, at: start.addingTimeInterval(2.9))

		XCTAssertEqual(sentLines(of: client), ["@+typing=active TAGMSG #chat"])

		client.noteLocalUserTyping("hell", in: channel, at: start.addingTimeInterval(3))

		XCTAssertEqual(client.sentLines.count, 2)
		XCTAssertEqual(sentLines(of: client).last, "@+typing=active TAGMSG #chat")
	}

	func testTypingPausedAfterIdleThenActiveAgain() {
		let client = makeMessageTagsClient()
		let channel = addChannel(named: "#chat", to: client)
		let start = Date()

		client.noteLocalUserTyping("h", in: channel, at: start)
		client.typingPauseTimerFired(channel)

		XCTAssertEqual(sentLines(of: client), [
			"@+typing=active TAGMSG #chat",
			"@+typing=paused TAGMSG #chat",
		])

		client.noteLocalUserTyping("he", in: channel, at: start.addingTimeInterval(0.5))

		XCTAssertEqual(sentLines(of: client).last, "@+typing=active TAGMSG #chat")
		XCTAssertEqual(client.sentLines.count, 3)
	}

	func testTypingDoneWhenTextClearedOrSent() {
		let client = makeMessageTagsClient()
		let channel = addChannel(named: "#chat", to: client)

		client.noteLocalUserTyping("h", in: channel, at: Date())
		client.noteLocalUserTyping("", in: channel, at: Date())

		XCTAssertEqual(sentLines(of: client), [
			"@+typing=active TAGMSG #chat",
			"@+typing=done TAGMSG #chat",
		])

		client.noteLocalUserTyping("", in: channel, at: Date())
		XCTAssertEqual(client.sentLines.count, 2)

		client.noteLocalUserTyping("x", in: channel, at: Date())
		client.localUserSentMessage(in: channel)

		XCTAssertEqual(sentLines(of: client).last, "@+typing=done TAGMSG #chat")
		XCTAssertEqual(client.sentLines.count, 4)
	}

	func testTypingIsNotSentForCommands() {
		let client = makeMessageTagsClient()
		let channel = addChannel(named: "#chat", to: client)

		client.noteLocalUserTyping("/", in: channel, at: Date())
		client.noteLocalUserTyping("/me", in: channel, at: Date())
		XCTAssertEqual(client.sentLines.count, 0)

		client.noteLocalUserTyping("h", in: channel, at: Date())
		client.noteLocalUserTyping("/h", in: channel, at: Date())

		XCTAssertEqual(sentLines(of: client), [
			"@+typing=active TAGMSG #chat",
			"@+typing=done TAGMSG #chat",
		])
	}

	func testTypingIsNotSentWithoutMessageTagsOrToConsole() {
		let client = GLTTestClient()
		client.markAsLoggedIn()
		let channel = addChannel(named: "#chat", to: client)

		client.noteLocalUserTyping("h", in: channel, at: Date())
		client.noteLocalUserTyping("h", in: nil, at: Date())
		XCTAssertEqual(client.sentLines.count, 0)

		let tagged = makeMessageTagsClient()
		tagged.noteLocalUserTyping("h", in: nil, at: Date())
		XCTAssertEqual(tagged.sentLines.count, 0)
	}

	func testTypingRespectsPreference() {
		TextualUserDefaults.shared().set(false, forKey: "SendTypingNotifications")
		let client = makeMessageTagsClient()
		let channel = addChannel(named: "#chat", to: client)

		client.noteLocalUserTyping("h", in: channel, at: Date())

		XCTAssertEqual(client.sentLines.count, 0)
	}

	func testTypingStateExpires() throws {
		let client = makeMessageTagsClient()
		let channel = addChannel(named: "#chat", to: client)
		let tracker = try XCTUnwrap(client.typingTracker)
		let start = Date()

		tracker.noteTypingState(.active, fromNickname: "mara", in: channel, at: start)
		tracker.noteTypingState(.paused, fromNickname: "jonas", in: channel, at: start)

		XCTAssertEqual(tracker.typingNicknames(in: channel, at: start.addingTimeInterval(5)), ["mara", "jonas"])
		XCTAssertEqual(tracker.typingNicknames(in: channel, at: start.addingTimeInterval(7)), ["jonas"])
		XCTAssertEqual(tracker.typingNicknames(in: channel, at: start.addingTimeInterval(31)), [])

		tracker.expireEntries(at: start.addingTimeInterval(31))

		XCTAssertEqual(tracker.typingNicknames(in: channel, at: start), [])
	}

	func testTypingDoneRemovesEntryAndTagMessageFeedsTracker() throws {
		let client = makeMessageTagsClient()
		let channel = addChannel(named: "#chat", to: client)
		let tracker = try XCTUnwrap(client.typingTracker)

		client.receiveTagMessage(message("@+typing=active :mara!u@h TAGMSG #chat", on: client))
		XCTAssertEqual(tracker.typingNicknames(in: channel), ["mara"])

		client.receiveTagMessage(message("@+typing=done :mara!u@h TAGMSG #chat", on: client))
		XCTAssertEqual(tracker.typingNicknames(in: channel), [])

		client.receiveTagMessage(message("@+typing=active :me!u@h TAGMSG #chat", on: client))
		XCTAssertEqual(tracker.typingNicknames(in: channel), [])
	}

	func testReplyTagIsSentOnFirstLineOnly() {
		let client = makeMessageTagsClient()
		let channel = addChannel(named: "#chat", to: client)
		client.nextMessageReplyIdentifier = "abc123"

		client.sendText(NSAttributedString(string: "first\nsecond"), as: .privmsg, to: channel)

		let privateMessages = sentLines(of: client).filter { $0.contains("PRIVMSG") }

		XCTAssertEqual(privateMessages, [
			"@+draft/reply=abc123 PRIVMSG #chat :first",
			"PRIVMSG #chat :second",
		])
		XCTAssertNil(client.nextMessageReplyIdentifier)
		let firstPrinted = client.printedLines.firstObject as? [String: Any]
		XCTAssertEqual(firstPrinted?["messageBody"] as? String, "first")

		client.sendText(NSAttributedString(string: "third"), as: .privmsg, to: channel)

		XCTAssertEqual(sentLines(of: client).last, "PRIVMSG #chat :third")
	}

	func testReplyTagIsDroppedWithoutMessageTags() {
		let client = GLTTestClient()
		client.markAsLoggedIn()
		let channel = addChannel(named: "#chat", to: client)
		client.nextMessageReplyIdentifier = "abc123"

		client.sendText(NSAttributedString(string: "hello"), as: .privmsg, to: channel)

		XCTAssertEqual(sentLines(of: client).last, "PRIVMSG #chat :hello")
	}

	func testReactionSendsTagMessage() {
		let client = makeMessageTagsClient()
		let channel = addChannel(named: "#chat", to: client)

		XCTAssertTrue(client.sendReaction("👍", toMessageIdentifier: "abc123", in: channel))
		XCTAssertEqual(sentLines(of: client), ["@+draft/react=👍;+draft/reply=abc123 TAGMSG #chat"])
	}

	func testReactionRequiresMessageTags() {
		let client = GLTTestClient()
		client.markAsLoggedIn()
		let channel = addChannel(named: "#chat", to: client)

		XCTAssertFalse(client.sendReaction("👍", toMessageIdentifier: "abc123", in: channel))
		XCTAssertEqual(client.sentLines.count, 0)
	}

	func testTagMessageEventShape() {
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

		XCTAssertEqual(event as NSDictionary, expected)

		let own = client.tagMessageEvent(
			withClientTags: tags,
			sender: "me",
			target: "#chat",
			timestamp: date,
			messageIdentifier: nil,
			account: nil
		)

		XCTAssertEqual(own["fromLocalUser"] as? Bool, true)
		XCTAssertNil(own["msgid"])
		XCTAssertNil(own["account"])
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

	private func addChannel(named name: String, to client: GLTTestClient) -> Channel {
		let channel = client.findChannelOrCreate(name)!

		channel.activate()

		return channel
	}

	private func message(_ line: String, on client: IRCClient) -> Message {
		Message(line: line, on: client)!
	}

	private func sentLines(of client: GLTTestClient) -> [String] {
		(client.sentLines as NSArray).compactMap { $0 as? String }
	}
}
