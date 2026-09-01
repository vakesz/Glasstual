/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
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

import Foundation
@testable import Glasstual
import Testing

@MainActor
@Suite("Chat history and batches", .serialized)
struct IRCClientHistoryTests {
	private static let joinLeavePreferenceKey = "DisplayEventInLogView -> Join, Part, Quit"

	private func makeHistoryClient() -> GLTTestClient {
		let client = GLTTestClient()
		client.enableCapability(.batch)
		client.enableCapability(.serverTime)
		client.enableCapability(.messageTags)
		client.enableCapability(.chatHistory)
		client.isLoggedIn = true

		return client
	}

	/// The netsplit summary is only printed with join and quit events shown,
	/// so the preference is set for the test and put back afterwards.
	private func withNetsplitClient(
		showingJoinsAndQuits showJoinLeave: Bool,
		_ body: (GLTTestClient) throws -> Void
	) rethrows {
		let defaults = TextualUserDefaults.container
		let original = defaults.object(forKey: Self.joinLeavePreferenceKey)
		defer {
			if let original {
				defaults.set(original, forKey: Self.joinLeavePreferenceKey)
			} else {
				defaults.removeObject(forKey: Self.joinLeavePreferenceKey)
			}
		}

		defaults.set(showJoinLeave, forKey: Self.joinLeavePreferenceKey)

		let client = GLTTestClient()
		client.enableCapability(.batch)
		client.forwardsProcessedMessages = true

		try body(client)
	}

	/// The historic log file keeps its per-view dedup index in a process-wide
	/// singleton, so anything indexed against a view outlives the test that
	/// indexed it unless the view is forgotten again.
	private func withChannel(
		named name: String,
		on client: GLTTestClient,
		_ body: (Channel) throws -> Void
	) throws {
		let channel = try #require(client.findChannelOrCreate(name))
		defer { LogControllerHistoricLogFile.shared().forgetView(channel.uniqueIdentifier) }

		try body(channel)
	}

	private func logLine(
		messageIdentifier: String?,
		nickname: String,
		text: String,
		date: Date
	) -> LogLine {
		var line = LogLine()
		line.command = "privmsg"
		line.lineType = .privateMessage
		line.messageIdentifier = messageIdentifier
		line.nickname = nickname
		line.messageBody = text
		line.receivedAt = date

		return line
	}

	private func index(_ line: LogLine, for channel: Channel) {
		LogControllerHistoricLogFile.shared().indexLogLine(line, forView: channel.uniqueIdentifier)
	}

	private func feed(_ lines: [String], to client: GLTTestClient) throws {
		for line in lines {
			let parsedMessage = try message(line, on: client)

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

	private func message(_ line: String, on client: IRCClient) throws -> Message {
		try #require(Message(line: line, on: client))
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

	@Test("Chat history is only requested once the capabilities it depends on are there")
	func chatHistoryIsRequestedOnlyWithItsDependencies() throws {
		let client = GLTTestClient()
		let partialList = try message(
			":irc.example.net CAP * LS :draft/chathistory draft/read-marker",
			on: client
		)

		client.receiveCapabilityOrAuthenticationRequest(partialList)

		#expect(capabilityCommands(of: client) == ["REQ draft/read-marker"])

		let complete = GLTTestClient()
		let completeList = try message(
			":irc.example.net CAP * LS :batch server-time message-tags chathistory read-marker",
			on: complete
		)

		complete.receiveCapabilityOrAuthenticationRequest(completeList)

		#expect(capabilityCommands(of: complete) == ["REQ message-tags"])
		#expect(complete.pendingCapabilityRequests == [
			"batch", "chathistory", "read-marker", "server-time",
		])

		let acknowledgement = try message(":irc.example.net CAP me ACK :chathistory", on: complete)

		complete.receiveCapabilityOrAuthenticationRequest(acknowledgement)

		#expect(complete.isCapabilityEnabled(.chatHistory))
	}

	@Test("The request limit comes from ISUPPORT, in either of its spellings")
	func chatHistoryLimitComesFromISupport() {
		let client = makeHistoryClient()

		#expect(client.chatHistoryRequestLimit() == 100)

		client.supportInfo.processConfigurationData("CHATHISTORY=50")
		#expect(client.supportInfo.chatHistoryMaximumLines == 50)
		#expect(client.chatHistoryRequestLimit() == 50)

		client.supportInfo.processConfigurationData("draft/CHATHISTORY=20")
		#expect(client.chatHistoryRequestLimit() == 20)

		client.supportInfo.processConfigurationData("CHATHISTORY=1000")
		#expect(client.chatHistoryRequestLimit() == 100)
	}

	@Test("A LATEST request asks from the newest local line once there is one")
	func latestRequestUsesStarWithoutLocalScrollbackAndTimestampWithIt() throws {
		let client = makeHistoryClient()

		try withChannel(named: "#chat", on: client) { channel in
			client.requestChatHistory(for: channel)
			#expect(sentLines(of: client) == ["CHATHISTORY LATEST #chat * 100"])

			let date = Date(timeIntervalSince1970: 1_700_000_000.5)
			index(logLine(messageIdentifier: "m1", nickname: "a", text: "hi", date: date), for: channel)

			client.requestChatHistory(for: channel)

			#expect(
				sentLines(of: client).last == "CHATHISTORY LATEST #chat timestamp=2023-11-14T22:13:20.500Z 100"
			)
		}
	}

	@Test("Nothing is requested without the chat history capability")
	func latestRequestNeedsTheCapability() throws {
		let client = GLTTestClient()
		client.isLoggedIn = true

		try withChannel(named: "#chat", on: client) { channel in
			client.requestChatHistory(for: channel)

			#expect(client.sentLines.count == 0)
		}
	}

	@Test("A BEFORE request is sent once per target until the server answers it")
	func beforeRequestIsSentOncePerTargetUntilAnswered() throws {
		let client = makeHistoryClient()

		try withChannel(named: "#chat", on: client) { channel in
			let oldest = Date(timeIntervalSince1970: 1_700_000_000)

			client.requestChatHistory(before: oldest, in: channel)
			client.requestChatHistory(before: oldest, in: channel)

			#expect(sentLines(of: client) == [
				"CHATHISTORY BEFORE #chat timestamp=2023-11-14T22:13:20.000Z 100",
			])

			try feed([
				":irc.example.net BATCH +h1 chathistory #chat",
				"@batch=h1;msgid=x1;time=2023-11-14T22:00:00.000Z :a!u@h PRIVMSG #chat :older",
				":irc.example.net BATCH -h1",
			], to: client)

			#expect(client.processedMessages.count == 1)

			client.requestChatHistory(before: Date(timeIntervalSince1970: 1_699_999_200), in: channel)
			#expect(client.sentLines.count == 2)
		}
	}

	@Test("A target the server refused is reported once and never asked again")
	func failedTargetIsReportedOnceAndNotRetried() throws {
		let client = makeHistoryClient()

		try withChannel(named: "#chat", on: client) { channel in
			let latestFailure = try message(
				":irc.example.net FAIL CHATHISTORY INVALID_TARGET LATEST #chat :No history for #chat",
				on: client
			)
			let beforeFailure = try message(
				":irc.example.net FAIL CHATHISTORY INVALID_TARGET BEFORE #chat :No history for #chat",
				on: client
			)

			client.receiveStandardReply(latestFailure)
			client.receiveStandardReply(beforeFailure)

			#expect(client.printedLines.count == 1)
			#expect(
				printedLine(at: 0, on: client)?["messageBody"] as? String
					== "FAIL CHATHISTORY/INVALID_TARGET: No history for #chat"
			)

			client.requestChatHistory(for: channel)
			client.requestChatHistory(before: Date(), in: channel)

			#expect(client.sentLines.count == 0)
		}
	}

	@Test("ZNC playback is only asked for when chat history is unavailable")
	func chatHistoryWinsOverZNCPlayback() {
		let client = makeHistoryClient()
		client.enableCapability(.playback)

		client.requestPlayback()
		#expect(client.sentLines.count == 0)

		client.disableCapability(.chatHistory)
		client.requestPlayback()

		#expect(sentLines(of: client) == ["PRIVMSG *playback :play * 0"])
	}

	@Test("A typed /chathistory command reaches the server unchanged")
	func chatHistoryCommandIsPassedThrough() {
		let client = makeHistoryClient()

		client.sendCommand(
			"/chathistory AROUND #chat timestamp=2023-11-14T22:13:20.000Z 10",
			completeTarget: false,
			target: nil
		)

		#expect(sentLines(of: client) == [
			"CHATHISTORY AROUND #chat timestamp=2023-11-14T22:13:20.000Z 10",
		])
	}

	@Test("A replayed line is marked historic, and one already on screen is dropped")
	func replayedLinesAreHistoricAndDeduplicatedByMessageIdentifier() throws {
		let client = makeHistoryClient()

		try withChannel(named: "#chat", on: client) { channel in
			let date = Date(timeIntervalSince1970: 1_700_000_000)

			index(logLine(messageIdentifier: "seen", nickname: "a", text: "one", date: date), for: channel)
			index(logLine(messageIdentifier: nil, nickname: "b", text: "two", date: date), for: channel)

			try feed([
				":irc.example.net BATCH +h1 chathistory #chat",
				"@batch=h1;msgid=seen;time=2023-11-14T22:13:20.000Z :a!u@h PRIVMSG #chat :one",
				"@batch=h1;time=2023-11-14T22:13:20.000Z :b!u@h PRIVMSG #chat :two",
				"@batch=h1;time=2023-11-14T22:13:20.000Z :b!u@h PRIVMSG #chat :two again",
				"@batch=h1;msgid=new;time=2023-11-14T22:13:21.000Z :c!u@h PRIVMSG #chat :three",
				":irc.example.net BATCH -h1",
			], to: client)

			let messages = processedMessages(of: client)
			let everyMessageIsHistoric = messages.allSatisfy(\.isHistoric)

			#expect(messages.map(\.sequence) == ["two again", "three"])
			#expect(everyMessageIsHistoric)
		}
	}

	@Test("Without a message identifier a duplicate is found by time, sender and text")
	func duplicateCheckFallsBackToTimestampSenderAndText() throws {
		let client = makeHistoryClient()

		try withChannel(named: "#chat", on: client) { channel in
			let date = Date(timeIntervalSince1970: 1_700_000_000)

			index(logLine(messageIdentifier: nil, nickname: "b", text: "two", date: date), for: channel)

			let sameLine = try message("@time=2023-11-14T22:13:20.000Z :b!u@h PRIVMSG #chat :two", on: client)
			let otherSender = try message("@time=2023-11-14T22:13:20.000Z :c!u@h PRIVMSG #chat :two", on: client)
			let otherTime = try message("@time=2023-11-14T22:13:21.000Z :b!u@h PRIVMSG #chat :two", on: client)
			let noTime = try message(":b!u@h PRIVMSG #chat :two", on: client)

			#expect(client.chatHistoryMessageIsDuplicate(sameLine))
			#expect(client.chatHistoryMessageIsDuplicate(otherSender) == false)
			#expect(client.chatHistoryMessageIsDuplicate(otherTime) == false)
			#expect(client.chatHistoryMessageIsDuplicate(noTime) == false)
		}
	}

	@Test("A read marker at the newest line clears the unread counts, and a star does not")
	func receivedReadMarkerAtNewestLineClearsUnreadCounts() throws {
		let client = makeHistoryClient()
		client.enableCapability(.readMarker)

		try withChannel(named: "#chat", on: client) { channel in
			let date = Date(timeIntervalSince1970: 1_700_000_000)

			index(logLine(messageIdentifier: "r1", nickname: "a", text: "hi", date: date), for: channel)
			channel.treeUnreadCount = 3
			channel.nicknameHighlightCount = 1

			let olderMarker = try message(
				":irc.example.net MARKREAD #chat timestamp=2023-11-14T22:13:19.000Z",
				on: client
			)
			let newestMarker = try message(
				":irc.example.net MARKREAD #chat timestamp=2023-11-14T22:13:20.000Z",
				on: client
			)
			let starMarker = try message(":irc.example.net MARKREAD #chat *", on: client)

			client.receiveReadMarker(olderMarker)

			#expect(channel.treeUnreadCount == 3)
			#expect(channel.nicknameHighlightCount == 1)

			client.receiveReadMarker(newestMarker)

			#expect(channel.treeUnreadCount == 0)
			#expect(channel.nicknameHighlightCount == 0)
			#expect(channel.isUnread == false)

			channel.treeUnreadCount = 1
			client.receiveReadMarker(starMarker)

			#expect(channel.treeUnreadCount == 1)
		}
	}

	@Test("A read marker is sent once for each newest line, not once per request")
	func readMarkerIsSentOncePerNewestLine() throws {
		let client = makeHistoryClient()
		client.enableCapability(.readMarker)

		try withChannel(named: "#chat", on: client) { channel in
			client.markChannel(asRead: channel)
			client.onReadMarkerTimer()
			#expect(client.sentLines.count == 0)

			let date = Date(timeIntervalSince1970: 1_700_000_000)
			index(logLine(messageIdentifier: "r1", nickname: "a", text: "hi", date: date), for: channel)

			client.markChannel(asRead: channel)
			client.markChannel(asRead: channel)
			client.onReadMarkerTimer()

			#expect(sentLines(of: client) == ["MARKREAD #chat timestamp=2023-11-14T22:13:20.000Z"])

			client.markChannel(asRead: channel)
			client.onReadMarkerTimer()
			#expect(client.sentLines.count == 1)

			index(
				logLine(messageIdentifier: "r2", nickname: "a", text: "again", date: date.addingTimeInterval(5)),
				for: channel
			)
			client.markChannel(asRead: channel)
			client.onReadMarkerTimer()

			#expect(sentLines(of: client).last == "MARKREAD #chat timestamp=2023-11-14T22:13:25.000Z")
			#expect(client.sentLines.count == 2)
		}
	}

	@Test("Selecting a channel asks for its history and its read marker")
	func readMarkerIsQueriedOnActivation() throws {
		let client = makeHistoryClient()
		client.enableCapability(.readMarker)

		try withChannel(named: "#chat", on: client) { channel in
			client.noteChannelActivated(channel)

			#expect(sentLines(of: client) == ["CHATHISTORY LATEST #chat * 100", "MARKREAD #chat"])
		}
	}

	@Test("No read marker is sent without the capability")
	func readMarkerIsNotSentWithoutTheCapability() throws {
		let client = makeHistoryClient()

		try withChannel(named: "#chat", on: client) { channel in
			index(logLine(messageIdentifier: "r1", nickname: "a", text: "hi", date: Date()), for: channel)
			client.sendReadMarker(for: channel)

			#expect(client.sentLines.count == 0)
		}
	}

	@Test("With join and quit events hidden the netsplit still updates the member list")
	func netsplitSummaryIsHiddenWithJoinsAndQuits() throws {
		try withNetsplitClient(showingJoinsAndQuits: false) { client in
			try withChannel(named: "#chat", on: client) { channel in
				channel.activate()
				try feed([":alice!u@h JOIN #chat"], to: client)
				let linesBefore = client.printedLines.count

				try feed([
					":irc.example.net BATCH +ns netsplit irc.hub irc.leaf",
					"@batch=ns :alice!u@h QUIT :irc.hub irc.leaf",
					":irc.example.net BATCH -ns",
				], to: client)

				#expect(channel.memberExists("alice") == false)
				#expect(client.printedLines.count == linesBefore)
			}
		}
	}

	@Test("A netsplit batch prints one summary line and takes its users out of the channel")
	func netsplitBatchProducesOneSummaryLineAndUpdatesMembers() throws {
		try withNetsplitClient(showingJoinsAndQuits: true) { client in
			try withChannel(named: "#chat", on: client) { channel in
				channel.activate()

				try feed([
					":alice!u@h JOIN #chat",
					":bob!u@h JOIN #chat",
					":carol!u@h JOIN #chat",
				], to: client)

				#expect(channel.memberExists("alice"))
				#expect(channel.memberExists("bob"))
				#expect(channel.memberExists("carol"))

				var linesBefore = client.printedLines.count
				try feed([
					":irc.example.net BATCH +ns netsplit irc.hub irc.leaf",
					"@batch=ns :alice!u@h QUIT :irc.hub irc.leaf",
					"@batch=ns :bob!u@h QUIT :irc.hub irc.leaf",
					":irc.example.net BATCH -ns",
				], to: client)

				#expect(channel.memberExists("alice") == false)
				#expect(channel.memberExists("bob") == false)
				#expect(channel.memberExists("carol"))

				var newLines = printedLines(from: linesBefore, on: client)
				#expect(newLines.count == 1)
				#expect(
					newLines.first?["messageBody"] as? String
						== "Netsplit between \u{2}irc.hub\u{2} and \u{2}irc.leaf\u{2}: 2 users left (alice, bob)"
				)
				#expect((newLines.first?["lineType"] as? NSNumber)?.uintValue == LogLineType.quit.rawValue)
				#expect(newLines.first?["channel"] as? Channel === channel)

				linesBefore = client.printedLines.count
				try feed([
					":irc.example.net BATCH +nj netjoin irc.hub irc.leaf",
					"@batch=nj :alice!u@h JOIN #chat",
					"@batch=nj :bob!u@h JOIN #chat",
					":irc.example.net BATCH -nj",
				], to: client)

				#expect(channel.memberExists("alice"))
				#expect(channel.memberExists("bob"))

				newLines = printedLines(from: linesBefore, on: client)
				#expect(newLines.count == 1)
				#expect(
					newLines.first?["messageBody"] as? String
						== "Netjoin between \u{2}irc.hub\u{2} and \u{2}irc.leaf\u{2}: 2 users rejoined (alice, bob)"
				)
				#expect((newLines.first?["lineType"] as? NSNumber)?.uintValue == LogLineType.join.rawValue)
			}
		}
	}

	@Test("A netsplit summary names ten users and counts the rest")
	func netsplitSummaryListsAtMostTenNicknames() throws {
		try withNetsplitClient(showingJoinsAndQuits: true) { client in
			try withChannel(named: "#chat", on: client) { channel in
				channel.activate()

				let joins = (1 ... 12).map { ":user\($0)!u@h JOIN #chat" }
				var quits = [":irc.example.net BATCH +ns netsplit irc.hub irc.leaf"]
				quits.append(contentsOf: (1 ... 12).map { "@batch=ns :user\($0)!u@h QUIT :split" })
				quits.append(":irc.example.net BATCH -ns")

				try feed(joins, to: client)
				let linesBefore = client.printedLines.count
				try feed(quits, to: client)

				#expect(client.printedLines.count == linesBefore + 1)
				#expect(
					(client.printedLines.lastObject as? [String: Any])?["messageBody"] as? String
						== "Netsplit between \u{2}irc.hub\u{2} and \u{2}irc.leaf\u{2}: 12 users left " +
						"(user1, user2, user3, user4, user5, user6, user7, user8, user9, user10, … and 2 more)"
				)
				#expect(channel.memberExists("user1") == false)
				#expect(channel.memberExists("user12") == false)
			}
		}
	}
}
