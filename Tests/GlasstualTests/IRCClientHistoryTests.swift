/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \\ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
 * Copyright (c) 2010 - 2018 Codeux Software, LLC & respective contributors.
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

final class IRCClientHistoryTests: XCTestCase {
	private static let joinLeavePreferenceKey = "DisplayEventInLogView -> Join, Part, Quit"
	private var previousJoinLeavePreference: Any?
	private var changedJoinLeavePreference = false

	override func tearDown() {
		if changedJoinLeavePreference {
			let defaults = TPCPreferencesUserDefaults.shared()

			if let previousJoinLeavePreference {
				defaults.set(previousJoinLeavePreference, forKey: Self.joinLeavePreferenceKey)
			} else {
				defaults.removeObject(forKey: Self.joinLeavePreferenceKey)
			}
		}

		previousJoinLeavePreference = nil
		changedJoinLeavePreference = false

		super.tearDown()
	}

	func testChatHistoryIsRequestedOnlyWithItsDependencies() {
		let client = GLTTestClient()

		client.receiveCapabilityOrAuthenticationRequest(message(
			":irc.example.net CAP * LS :draft/chathistory draft/read-marker",
			on: client
		))

		XCTAssertEqual(capabilityCommands(of: client), ["REQ draft/read-marker"])

		let complete = GLTTestClient()
		complete.receiveCapabilityOrAuthenticationRequest(message(
			":irc.example.net CAP * LS :batch server-time message-tags chathistory read-marker",
			on: complete
		))

		XCTAssertEqual(capabilityCommands(of: complete), ["REQ message-tags"])
		XCTAssertEqual(complete.pendingCapabilityRequests, [
			"batch", "chathistory", "read-marker", "server-time",
		])

		complete.receiveCapabilityOrAuthenticationRequest(message(
			":irc.example.net CAP me ACK :chathistory",
			on: complete
		))

		XCTAssertTrue(complete.isCapabilityEnabled(.chatHistory))
	}

	func testChatHistoryLimitComesFromISupport() {
		let client = makeHistoryClient()

		XCTAssertEqual(client.chatHistoryRequestLimit(), 100)

		client.supportInfo.processConfigurationData("CHATHISTORY=50")
		XCTAssertEqual(client.supportInfo.chatHistoryMaximumLines, 50)
		XCTAssertEqual(client.chatHistoryRequestLimit(), 50)

		client.supportInfo.processConfigurationData("draft/CHATHISTORY=20")
		XCTAssertEqual(client.chatHistoryRequestLimit(), 20)

		client.supportInfo.processConfigurationData("CHATHISTORY=1000")
		XCTAssertEqual(client.chatHistoryRequestLimit(), 100)
	}

	func testLatestRequestUsesStarWithoutLocalScrollbackAndTimestampWithIt() {
		let client = makeHistoryClient()
		let channel = makeChannel(named: "#chat", on: client)

		client.requestChatHistory(for: channel)
		XCTAssertEqual(sentLines(of: client), ["CHATHISTORY LATEST #chat * 100"])

		let date = Date(timeIntervalSince1970: 1_700_000_000.5)
		index(logLine(messageIdentifier: "m1", nickname: "a", text: "hi", date: date), for: channel)

		client.requestChatHistory(for: channel)

		XCTAssertEqual(
			sentLines(of: client).last,
			"CHATHISTORY LATEST #chat timestamp=2023-11-14T22:13:20.500Z 100"
		)
	}

	func testLatestRequestNeedsTheCapability() {
		let client = GLTTestClient()
		client.setValue(true, forKey: "isLoggedIn")
		let channel = makeChannel(named: "#chat", on: client)

		client.requestChatHistory(for: channel)

		XCTAssertEqual(client.sentLines.count, 0)
	}

	func testBeforeRequestIsSentOncePerTargetUntilAnswered() {
		let client = makeHistoryClient()
		let channel = makeChannel(named: "#chat", on: client)
		let oldest = Date(timeIntervalSince1970: 1_700_000_000)

		client.requestChatHistory(before: oldest, in: channel)
		client.requestChatHistory(before: oldest, in: channel)

		XCTAssertEqual(sentLines(of: client), [
			"CHATHISTORY BEFORE #chat timestamp=2023-11-14T22:13:20.000Z 100",
		])

		feed([
			":irc.example.net BATCH +h1 chathistory #chat",
			"@batch=h1;msgid=x1;time=2023-11-14T22:00:00.000Z :a!u@h PRIVMSG #chat :older",
			":irc.example.net BATCH -h1",
		], to: client)

		XCTAssertEqual(client.processedMessages.count, 1)

		client.requestChatHistory(before: Date(timeIntervalSince1970: 1_699_999_200), in: channel)
		XCTAssertEqual(client.sentLines.count, 2)
	}

	func testFailedTargetIsReportedOnceAndNotRetried() {
		let client = makeHistoryClient()
		let channel = makeChannel(named: "#chat", on: client)

		client.receiveStandardReply(message(
			":irc.example.net FAIL CHATHISTORY INVALID_TARGET LATEST #chat :No history for #chat",
			on: client
		))
		client.receiveStandardReply(message(
			":irc.example.net FAIL CHATHISTORY INVALID_TARGET BEFORE #chat :No history for #chat",
			on: client
		))

		XCTAssertEqual(client.printedLines.count, 1)
		XCTAssertEqual(
			printedLine(at: 0, on: client)?["messageBody"] as? String,
			"FAIL CHATHISTORY/INVALID_TARGET: No history for #chat"
		)

		client.requestChatHistory(for: channel)
		client.requestChatHistory(before: Date(), in: channel)

		XCTAssertEqual(client.sentLines.count, 0)
	}

	func testChatHistoryWinsOverZNCPlayback() {
		let client = makeHistoryClient()
		client.enableCapability(.playback)

		client.requestPlayback()
		XCTAssertEqual(client.sentLines.count, 0)

		client.disableCapability(.chatHistory)
		client.requestPlayback()

		XCTAssertEqual(sentLines(of: client), ["PRIVMSG *playback :play * 0"])
	}

	func testChatHistoryCommandIsPassedThrough() {
		let client = makeHistoryClient()

		client.sendCommand(
			"/chathistory AROUND #chat timestamp=2023-11-14T22:13:20.000Z 10",
			completeTarget: false,
			target: nil
		)

		XCTAssertEqual(sentLines(of: client), [
			"CHATHISTORY AROUND #chat timestamp=2023-11-14T22:13:20.000Z 10",
		])
	}

	func testReplayedLinesAreHistoricAndDeduplicatedByMessageIdentifier() {
		let client = makeHistoryClient()
		let channel = makeChannel(named: "#chat", on: client)
		let date = Date(timeIntervalSince1970: 1_700_000_000)

		index(logLine(messageIdentifier: "seen", nickname: "a", text: "one", date: date), for: channel)
		index(logLine(messageIdentifier: nil, nickname: "b", text: "two", date: date), for: channel)

		feed([
			":irc.example.net BATCH +h1 chathistory #chat",
			"@batch=h1;msgid=seen;time=2023-11-14T22:13:20.000Z :a!u@h PRIVMSG #chat :one",
			"@batch=h1;time=2023-11-14T22:13:20.000Z :b!u@h PRIVMSG #chat :two",
			"@batch=h1;time=2023-11-14T22:13:20.000Z :b!u@h PRIVMSG #chat :two again",
			"@batch=h1;msgid=new;time=2023-11-14T22:13:21.000Z :c!u@h PRIVMSG #chat :three",
			":irc.example.net BATCH -h1",
		], to: client)

		let messages = processedMessages(of: client)
		XCTAssertEqual(messages.map(\.sequence), ["two again", "three"])
		XCTAssertTrue(messages.allSatisfy(\.isHistoric))
	}

	func testDuplicateCheckFallsBackToTimestampSenderAndText() {
		let client = makeHistoryClient()
		let channel = makeChannel(named: "#chat", on: client)
		let date = Date(timeIntervalSince1970: 1_700_000_000)

		index(logLine(messageIdentifier: nil, nickname: "b", text: "two", date: date), for: channel)

		XCTAssertTrue(client.chatHistoryMessageIsDuplicate(message(
			"@time=2023-11-14T22:13:20.000Z :b!u@h PRIVMSG #chat :two",
			on: client
		)))
		XCTAssertFalse(client.chatHistoryMessageIsDuplicate(message(
			"@time=2023-11-14T22:13:20.000Z :c!u@h PRIVMSG #chat :two",
			on: client
		)))
		XCTAssertFalse(client.chatHistoryMessageIsDuplicate(message(
			"@time=2023-11-14T22:13:21.000Z :b!u@h PRIVMSG #chat :two",
			on: client
		)))
		XCTAssertFalse(client.chatHistoryMessageIsDuplicate(message(
			":b!u@h PRIVMSG #chat :two",
			on: client
		)))
	}

	func testReceivedReadMarkerAtNewestLineClearsUnreadCounts() {
		let client = makeHistoryClient()
		client.enableCapability(.readMarker)
		let channel = makeChannel(named: "#chat", on: client)
		let date = Date(timeIntervalSince1970: 1_700_000_000)

		index(logLine(messageIdentifier: "r1", nickname: "a", text: "hi", date: date), for: channel)
		channel.treeUnreadCount = 3
		channel.nicknameHighlightCount = 1

		client.receiveReadMarker(message(
			":irc.example.net MARKREAD #chat timestamp=2023-11-14T22:13:19.000Z",
			on: client
		))

		XCTAssertEqual(channel.treeUnreadCount, 3)
		XCTAssertEqual(channel.nicknameHighlightCount, 1)

		client.receiveReadMarker(message(
			":irc.example.net MARKREAD #chat timestamp=2023-11-14T22:13:20.000Z",
			on: client
		))

		XCTAssertEqual(channel.treeUnreadCount, 0)
		XCTAssertEqual(channel.nicknameHighlightCount, 0)
		XCTAssertFalse(channel.isUnread)

		channel.treeUnreadCount = 1
		client.receiveReadMarker(message(":irc.example.net MARKREAD #chat *", on: client))

		XCTAssertEqual(channel.treeUnreadCount, 1)
	}

	func testReadMarkerIsSentOncePerNewestLine() {
		let client = makeHistoryClient()
		client.enableCapability(.readMarker)
		let channel = makeChannel(named: "#chat", on: client)

		client.markChannel(asRead: channel)
		client.onReadMarkerTimer()
		XCTAssertEqual(client.sentLines.count, 0)

		let date = Date(timeIntervalSince1970: 1_700_000_000)
		index(logLine(messageIdentifier: "r1", nickname: "a", text: "hi", date: date), for: channel)

		client.markChannel(asRead: channel)
		client.markChannel(asRead: channel)
		client.onReadMarkerTimer()

		XCTAssertEqual(sentLines(of: client), ["MARKREAD #chat timestamp=2023-11-14T22:13:20.000Z"])

		client.markChannel(asRead: channel)
		client.onReadMarkerTimer()
		XCTAssertEqual(client.sentLines.count, 1)

		index(
			logLine(messageIdentifier: "r2", nickname: "a", text: "again", date: date.addingTimeInterval(5)),
			for: channel
		)
		client.markChannel(asRead: channel)
		client.onReadMarkerTimer()

		XCTAssertEqual(sentLines(of: client).last, "MARKREAD #chat timestamp=2023-11-14T22:13:25.000Z")
		XCTAssertEqual(client.sentLines.count, 2)
	}

	func testReadMarkerIsQueriedOnActivation() {
		let client = makeHistoryClient()
		client.enableCapability(.readMarker)
		let channel = makeChannel(named: "#chat", on: client)

		client.noteChannelActivated(channel)

		XCTAssertEqual(sentLines(of: client), ["CHATHISTORY LATEST #chat * 100", "MARKREAD #chat"])
	}

	func testReadMarkerIsNotSentWithoutTheCapability() {
		let client = makeHistoryClient()
		let channel = makeChannel(named: "#chat", on: client)

		index(logLine(messageIdentifier: "r1", nickname: "a", text: "hi", date: Date()), for: channel)
		client.sendReadMarker(for: channel)

		XCTAssertEqual(client.sentLines.count, 0)
	}

	func testNetsplitSummaryIsHiddenWithJoinsAndQuits() {
		let client = makeNetsplitClient(showingJoinsAndQuits: false)
		let channel = makeChannel(named: "#chat", on: client)
		channel.activate()
		feed([":alice!u@h JOIN #chat"], to: client)
		let linesBefore = client.printedLines.count

		feed([
			":irc.example.net BATCH +ns netsplit irc.hub irc.leaf",
			"@batch=ns :alice!u@h QUIT :irc.hub irc.leaf",
			":irc.example.net BATCH -ns",
		], to: client)

		XCTAssertFalse(channel.memberExists("alice"))
		XCTAssertEqual(client.printedLines.count, linesBefore)
	}

	func testNetsplitBatchProducesOneSummaryLineAndUpdatesMembers() {
		let client = makeNetsplitClient(showingJoinsAndQuits: true)
		let channel = makeChannel(named: "#chat", on: client)
		channel.activate()

		feed([
			":alice!u@h JOIN #chat",
			":bob!u@h JOIN #chat",
			":carol!u@h JOIN #chat",
		], to: client)

		XCTAssertTrue(channel.memberExists("alice"))
		XCTAssertTrue(channel.memberExists("bob"))
		XCTAssertTrue(channel.memberExists("carol"))

		var linesBefore = client.printedLines.count
		feed([
			":irc.example.net BATCH +ns netsplit irc.hub irc.leaf",
			"@batch=ns :alice!u@h QUIT :irc.hub irc.leaf",
			"@batch=ns :bob!u@h QUIT :irc.hub irc.leaf",
			":irc.example.net BATCH -ns",
		], to: client)

		XCTAssertFalse(channel.memberExists("alice"))
		XCTAssertFalse(channel.memberExists("bob"))
		XCTAssertTrue(channel.memberExists("carol"))

		var newLines = printedLines(from: linesBefore, on: client)
		XCTAssertEqual(newLines.count, 1)
		XCTAssertEqual(
			newLines.first?["messageBody"] as? String,
			"Netsplit between \u{2}irc.hub\u{2} and \u{2}irc.leaf\u{2}: 2 users left (alice, bob)"
		)
		XCTAssertEqual((newLines.first?["lineType"] as? NSNumber)?.uintValue, TVCLogLineType.quit.rawValue)
		XCTAssertTrue(newLines.first?["channel"] as? IRCChannel === channel)

		linesBefore = client.printedLines.count
		feed([
			":irc.example.net BATCH +nj netjoin irc.hub irc.leaf",
			"@batch=nj :alice!u@h JOIN #chat",
			"@batch=nj :bob!u@h JOIN #chat",
			":irc.example.net BATCH -nj",
		], to: client)

		XCTAssertTrue(channel.memberExists("alice"))
		XCTAssertTrue(channel.memberExists("bob"))

		newLines = printedLines(from: linesBefore, on: client)
		XCTAssertEqual(newLines.count, 1)
		XCTAssertEqual(
			newLines.first?["messageBody"] as? String,
			"Netjoin between \u{2}irc.hub\u{2} and \u{2}irc.leaf\u{2}: 2 users rejoined (alice, bob)"
		)
		XCTAssertEqual((newLines.first?["lineType"] as? NSNumber)?.uintValue, TVCLogLineType.join.rawValue)
	}

	func testNetsplitSummaryListsAtMostTenNicknames() {
		let client = makeNetsplitClient(showingJoinsAndQuits: true)
		let channel = makeChannel(named: "#chat", on: client)
		channel.activate()

		let joins = (1 ... 12).map { ":user\($0)!u@h JOIN #chat" }
		var quits = [":irc.example.net BATCH +ns netsplit irc.hub irc.leaf"]
		quits.append(contentsOf: (1 ... 12).map { "@batch=ns :user\($0)!u@h QUIT :split" })
		quits.append(":irc.example.net BATCH -ns")

		feed(joins, to: client)
		let linesBefore = client.printedLines.count
		feed(quits, to: client)

		XCTAssertEqual(client.printedLines.count, linesBefore + 1)
		XCTAssertEqual(
			(client.printedLines.lastObject as? [String: Any])?["messageBody"] as? String,
			"Netsplit between \u{2}irc.hub\u{2} and \u{2}irc.leaf\u{2}: 12 users left " +
				"(user1, user2, user3, user4, user5, user6, user7, user8, user9, user10, … and 2 more)"
		)
		XCTAssertFalse(channel.memberExists("user1"))
		XCTAssertFalse(channel.memberExists("user12"))
	}

	private func makeHistoryClient() -> GLTTestClient {
		let client = GLTTestClient()
		client.enableCapability(.batch)
		client.enableCapability(.serverTime)
		client.enableCapability(.messageTags)
		client.enableCapability(.chatHistory)
		client.setValue(true, forKey: "isLoggedIn")

		return client
	}

	private func makeNetsplitClient(showingJoinsAndQuits showJoinLeave: Bool) -> GLTTestClient {
		let defaults = TPCPreferencesUserDefaults.shared()
		previousJoinLeavePreference = defaults.object(forKey: Self.joinLeavePreferenceKey)
		changedJoinLeavePreference = true

		defaults.set(showJoinLeave, forKey: Self.joinLeavePreferenceKey)

		let client = GLTTestClient()
		client.enableCapability(.batch)
		client.forwardsProcessedMessages = true

		return client
	}

	private func makeChannel(named name: String, on client: GLTTestClient) -> IRCChannel {
		client.findChannelOrCreate(name)!
	}

	private func logLine(
		messageIdentifier: String?,
		nickname: String,
		text: String,
		date: Date
	) -> TVCLogLine {
		let line = TVCLogLineMutable()
		line.command = "privmsg"
		line.lineType = .privateMessage
		line.messageIdentifier = messageIdentifier
		line.nickname = nickname
		line.messageBody = text
		line.receivedAt = date

		return line.copy() as! TVCLogLine
	}

	private func index(_ line: TVCLogLine, for channel: IRCChannel) {
		let treeItem = (channel as AnyObject) as! IRCTreeItem
		LogControllerHistoricLogFile.shared().indexLogLine(line, for: treeItem)
	}

	private func feed(_ lines: [String], to client: GLTTestClient) {
		for line in lines {
			let parsedMessage = message(line, on: client)

			if client.filterBatchCommandIncomingData(parsedMessage) {
				continue
			}

			if parsedMessage.command == "BATCH" {
				client.receiveBatch(parsedMessage)
			} else {
				client.processIncomingMessage(parsedMessage)
			}
		}
	}

	private func message(_ line: String, on client: IRCClient) -> Message {
		Message(line: line, on: client)!
	}

	private func sentLines(of client: GLTTestClient) -> [String] {
		(client.sentLines as NSArray).compactMap { $0 as? String }
	}

	private func capabilityCommands(of client: GLTTestClient) -> [String] {
		(client.sentCapabilityCommands as NSArray).compactMap { $0 as? String }
	}

	private func processedMessages(of client: GLTTestClient) -> [Message] {
		(client.processedMessages as NSArray).compactMap { $0 as? Message }
	}

	private func printedLine(at index: Int, on client: GLTTestClient) -> [String: Any]? {
		client.printedLines[index] as? [String: Any]
	}

	private func printedLines(from index: Int, on client: GLTTestClient) -> [[String: Any]] {
		let count = client.printedLines.count - index
		guard count > 0 else { return [] }

		return (client.printedLines.subarray(with: NSRange(location: index, length: count)) as NSArray)
			.compactMap { $0 as? [String: Any] }
	}
}
