// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2018 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing

@MainActor
@Suite("Chat history and batches", .serialized)
struct ServerSessionHistoryTests {
	private static let joinLeaveSettingsKey = SettingsKeys.Messages.showJoinLeave.name

	private func makeHistorySession() -> TestServerSession {
		let session = TestServerSession()
		session.enableCapability(.batch)
		session.enableCapability(.serverTime)
		session.enableCapability(.messageTags)
		session.enableCapability(.chatHistory)
		session.isLoggedIn = true

		return session
	}

	/// The netsplit summary is only printed with join and quit events shown,
	/// so the setting is set for the test and put back afterwards.
	private func withNetsplitSession(
		showingJoinsAndQuits showJoinLeave: Bool,
		_ body: (TestServerSession) throws -> Void
	) rethrows {
		let defaults = GlasstualUserDefaults.container
		let original = defaults.object(forKey: Self.joinLeaveSettingsKey)
		defer {
			if let original {
				defaults.set(original, forKey: Self.joinLeaveSettingsKey)
			} else {
				defaults.removeObject(forKey: Self.joinLeaveSettingsKey)
			}
		}

		defaults.set(showJoinLeave, forKey: Self.joinLeaveSettingsKey)

		let session = TestServerSession()
		session.enableCapability(.batch)
		session.forwardsProcessedMessages = true

		try body(session)
	}

	/// The scrollback database keeps its per-view dedup index in a process-wide
	/// singleton, so anything indexed against a view outlives the test that
	/// indexed it unless the view is forgotten again.
	private func withChannel(
		named name: String,
		on session: TestServerSession,
		_ body: (Conversation) throws -> Void
	) throws {
		let channel = try #require(session.findConversationOrCreate(name))
		defer { Scrollback.shared.removeHistory(forView: channel.uniqueIdentifier, forget: true) }

		try body(channel)
	}

	private func chatLine(
		messageIdentifier: String?,
		nickname: String,
		text: String,
		date: Date
	) -> ChatLine {
		var line = ChatLine()
		line.command = "privmsg"
		line.lineType = .privateMessage
		line.messageIdentifier = messageIdentifier
		line.nickname = nickname
		line.messageBody = text
		line.receivedAt = date

		return line
	}

	private func index(_ line: ChatLine, for channel: Conversation) {
		Scrollback.shared.duplicates.indexChatLine(line, forView: channel.uniqueIdentifier)
	}

	private func feed(_ lines: [String], to session: TestServerSession) throws {
		for line in lines {
			let parsedMessage = try message(line, on: session)

			if session.filterBatchCommandIncomingData(parsedMessage) {
				continue
			}

			if parsedMessage.command == "BATCH" {
				session.receiveBatch(parsedMessage)
			} else {
				session.processIncomingMessage(parsedMessage)
			}
		}
	}

	private func message(_ line: String, on session: ServerSession) throws -> Message {
		try #require(Message(line: line, on: session))
	}

	private func sentLines(of session: TestServerSession) -> [String] {
		(session.sentLines as NSArray).compactMap { $0 as? String }
	}

	private func capabilityCommands(of session: TestServerSession) -> [String] {
		(session.sentCapabilityCommands as NSArray).compactMap { $0 as? String }
	}

	private func printedLine(at index: Int, on session: TestServerSession) -> [String: Any]? {
		session.printedLines[index] as? [String: Any]
	}

	private func printedLines(from index: Int, on session: TestServerSession) -> [[String: Any]] {
		let count = session.printedLines.count - index
		guard count > 0 else { return [] }

		return (session.printedLines.subarray(with: NSRange(location: index, length: count)) as NSArray)
			.compactMap { $0 as? [String: Any] }
	}

	@Test("Chat history is only requested once the capabilities it depends on are there")
	func chatHistoryIsRequestedOnlyWithItsDependencies() throws {
		let session = TestServerSession()
		let partialList = try message(
			":irc.example.net CAP * LS :draft/chathistory draft/read-marker",
			on: session
		)

		session.handleCapabilityOrAuthenticationRequest(partialList)

		#expect(capabilityCommands(of: session) == ["REQ draft/read-marker"])

		let complete = TestServerSession()
		let completeList = try message(
			":irc.example.net CAP * LS :batch server-time message-tags chathistory read-marker",
			on: complete
		)

		complete.handleCapabilityOrAuthenticationRequest(completeList)

		/* `chathistory` waits: its dependencies are offered but not yet
		 acknowledged, so only the four that stand on their own go out. */
		#expect(capabilityCommands(of: complete) == [
			"REQ message-tags batch read-marker server-time",
		])

		let acknowledgement = try message(":irc.example.net CAP me ACK :chathistory", on: complete)

		complete.handleCapabilityOrAuthenticationRequest(acknowledgement)

		#expect(complete.isCapabilityEnabled(.chatHistory) == false)
		try complete.handleCapabilityOrAuthenticationRequest(message(
			":irc.example.net CAP me ACK :batch server-time message-tags", on: complete
		))
		#expect(complete.isCapabilityEnabled(.chatHistory))
	}

	@Test("The request limit comes from ISUPPORT, in either of its spellings")
	func chatHistoryLimitComesFromISupport() {
		let session = makeHistorySession()

		#expect(session.chatHistoryRequestLimit() == 100)

		session.supportInfo.processConfigurationData("CHATHISTORY=50")
		#expect(session.supportInfo.chatHistoryMaximumLines == 50)
		#expect(session.chatHistoryRequestLimit() == 50)

		session.supportInfo.processConfigurationData("draft/CHATHISTORY=20")
		#expect(session.chatHistoryRequestLimit() == 20)

		session.supportInfo.processConfigurationData("CHATHISTORY=1000")
		#expect(session.chatHistoryRequestLimit() == 100)
	}

	@Test("A LATEST request asks from the newest local line once there is one")
	func latestRequestUsesStarWithoutLocalScrollbackAndTimestampWithIt() throws {
		let session = makeHistorySession()

		try withChannel(named: "#chat", on: session) { channel in
			session.requestChatHistory(for: channel)
			#expect(sentLines(of: session) == ["CHATHISTORY LATEST #chat * 100"])

			let date = Date(timeIntervalSince1970: 1_700_000_000.5)
			index(chatLine(messageIdentifier: "m1", nickname: "a", text: "hi", date: date), for: channel)

			session.requestChatHistory(for: channel)

			#expect(
				sentLines(of: session).last == "CHATHISTORY LATEST #chat timestamp=2023-11-14T22:13:20.500Z 100"
			)
		}
	}

	@Test("Nothing is requested without the chat history capability")
	func latestRequestNeedsTheCapability() throws {
		let session = TestServerSession()
		session.isLoggedIn = true

		try withChannel(named: "#chat", on: session) { channel in
			session.requestChatHistory(for: channel)

			#expect(session.sentLines.count == 0)
		}
	}

	@Test("A BEFORE request is sent once per target until the server answers it")
	func beforeRequestIsSentOncePerTargetUntilAnswered() throws {
		let session = makeHistorySession()

		try withChannel(named: "#chat", on: session) { channel in
			let oldest = Date(timeIntervalSince1970: 1_700_000_000)

			session.requestChatHistory(before: oldest, in: channel)
			session.requestChatHistory(before: oldest, in: channel)

			#expect(sentLines(of: session) == [
				"CHATHISTORY BEFORE #chat timestamp=2023-11-14T22:13:20.000Z 100",
			])

			try feed([
				":irc.example.net BATCH +h1 chathistory #chat",
				"@batch=h1;msgid=x1;time=2023-11-14T22:00:00.000Z :a!u@h PRIVMSG #chat :older",
				":irc.example.net BATCH -h1",
			], to: session)

			#expect(session.processedMessages.count == 1)

			session.requestChatHistory(before: Date(timeIntervalSince1970: 1_699_999_200), in: channel)
			#expect(session.sentLines.count == 2)
		}
	}

	@Test("A target the server refused is reported once and never asked again")
	func failedTargetIsReportedOnceAndNotRetried() throws {
		let session = makeHistorySession()

		try withChannel(named: "#chat", on: session) { channel in
			let latestFailure = try message(
				":irc.example.net FAIL CHATHISTORY INVALID_TARGET LATEST #chat :No history for #chat",
				on: session
			)
			let beforeFailure = try message(
				":irc.example.net FAIL CHATHISTORY INVALID_TARGET BEFORE #chat :No history for #chat",
				on: session
			)

			session.receiveStandardReply(latestFailure)
			session.receiveStandardReply(beforeFailure)

			#expect(session.printedLines.count == 1)
			#expect(
				printedLine(at: 0, on: session)?["messageBody"] as? String
					== "FAIL CHATHISTORY/INVALID_TARGET: No history for #chat"
			)

			session.requestChatHistory(for: channel)
			session.requestChatHistory(before: Date(), in: channel)

			#expect(session.sentLines.count == 0)
		}
	}

	@Test("Cancelling an unlabeled BEFORE retires its slot until the old wire response arrives")
	func unlabeledCancellationCannotConsumeARetry() throws {
		let session = makeHistorySession()
		try withChannel(named: "#chat", on: session) { channel in
			session.isConnected = true
			let socket = Connection(config: ConnectionConfig(), onSession: session)
			session.socket = socket
			let before = Date(timeIntervalSince1970: 100)
			session.requestChatHistory(before: before, in: channel)
			let pending = try #require(session.chatHistory.serverRequests[channel.uniqueIdentifier])
			session.cancelServerHistoryRequest(pending.request)
			session.requestChatHistory(before: before, in: channel)
			#expect(session.sentLines.count == 1)
			for wire in [
				"BATCH +retired chathistory #chat",
				"@batch=retired;time=1970-01-01T00:00:50.000Z :alice!u@h PRIVMSG #chat :retired",
				"BATCH -retired",
			] {
				session.connectionDidReceive(wire)
			}
			#expect(session.processedMessages.count == 0)
			#expect(session.chatHistory.serverRequests.isEmpty)
			session.requestChatHistory(before: before, in: channel)
			#expect(session.sentLines.count == 2)
			session.resetChatHistoryState()
		}
	}

	/** The retired slot is what the transcript has to be able to see.

	 An unlabelled request that timed out keeps its slot for the rest of the
	 connection, so a Retry button would send nothing. The view asks first and
	 hides the button instead of offering a dead one. */
	@Test("A retired slot reports that no retry is possible")
	func retiredSlotReportsThatRetryIsUnavailable() throws {
		let session = makeHistorySession()
		try withChannel(named: "#chat", on: session) { channel in
			#expect(session.canRetryServerHistory(for: channel))

			let before = Date(timeIntervalSince1970: 100)
			session.requestChatHistory(before: before, in: channel)

			// A request in flight is not a retry opportunity either.
			#expect(session.canRetryServerHistory(for: channel) == false)

			let pending = try #require(session.chatHistory.serverRequests[channel.uniqueIdentifier])
			session.cancelServerHistoryRequest(pending.request)

			#expect(session.chatHistory.serverRequests[channel.uniqueIdentifier] != nil)
			#expect(session.canRetryServerHistory(for: channel) == false)

			session.resetChatHistoryState()

			#expect(session.canRetryServerHistory(for: channel))
		}
	}

	@Test("ZNC playback is only asked for when chat history is unavailable")
	func chatHistoryWinsOverZNCPlayback() {
		let session = makeHistorySession()
		session.enableCapability(.playback)

		session.requestPlayback()
		#expect(session.sentLines.count == 0)

		session.disableCapability(.chatHistory)
		session.requestPlayback()

		#expect(sentLines(of: session) == ["PRIVMSG *playback :play * 0"])
	}

	@Test("A typed /chathistory command reaches the server unchanged")
	func chatHistoryCommandIsPassedThrough() {
		let session = makeHistorySession()

		session.sendCommand(
			"/chathistory AROUND #chat timestamp=2023-11-14T22:13:20.000Z 10",
			completeTarget: false,
			target: nil
		)

		#expect(sentLines(of: session) == [
			"CHATHISTORY AROUND #chat timestamp=2023-11-14T22:13:20.000Z 10",
		])
	}

	@Test("A replayed line is marked replayed, and one already on screen is dropped")
	func replayedLinesAreMarkedAndDeduplicatedByMessageIdentifier() throws {
		let session = makeHistorySession()

		try withChannel(named: "#chat", on: session) { channel in
			let date = Date(timeIntervalSince1970: 1_700_000_000)

			index(chatLine(messageIdentifier: "seen", nickname: "a", text: "one", date: date), for: channel)
			index(chatLine(messageIdentifier: nil, nickname: "b", text: "two", date: date), for: channel)

			try feed([
				":irc.example.net BATCH +h1 chathistory #chat",
				"@batch=h1;msgid=seen;time=2023-11-14T22:13:20.000Z :a!u@h PRIVMSG #chat :one",
				"@batch=h1;time=2023-11-14T22:13:20.000Z :b!u@h PRIVMSG #chat :two",
				"@batch=h1;time=2023-11-14T22:13:20.000Z :b!u@h PRIVMSG #chat :two again",
				"@batch=h1;msgid=new;time=2023-11-14T22:13:21.000Z :c!u@h PRIVMSG #chat :three",
				":irc.example.net BATCH -h1",
			], to: session)

			let messages = session.processedMessages
			let everyMessageIsReplayed = messages.allSatisfy(\.isReplayed)

			#expect(messages.map(\.sequence) == ["two again", "three"])
			#expect(everyMessageIsReplayed)
		}
	}

	@Test("Without a message identifier a duplicate is found by time, sender and text")
	func duplicateCheckFallsBackToTimestampSenderAndText() throws {
		let session = makeHistorySession()

		try withChannel(named: "#chat", on: session) { channel in
			let date = Date(timeIntervalSince1970: 1_700_000_000)

			index(chatLine(messageIdentifier: nil, nickname: "b", text: "two", date: date), for: channel)

			var sameLine = try message("@time=2023-11-14T22:13:20.000Z :b!u@h PRIVMSG #chat :two", on: session)
			var otherSender = try message("@time=2023-11-14T22:13:20.000Z :c!u@h PRIVMSG #chat :two", on: session)
			var otherTime = try message("@time=2023-11-14T22:13:21.000Z :b!u@h PRIVMSG #chat :two", on: session)
			let noTime = try message(":b!u@h PRIVMSG #chat :two", on: session)

			sameLine.isReplayed = true
			otherSender.isReplayed = true
			otherTime.isReplayed = true
			#expect(session.chatHistoryMessageIsDuplicate(sameLine))
			#expect(session.chatHistoryMessageIsDuplicate(otherSender) == false)
			#expect(session.chatHistoryMessageIsDuplicate(otherTime) == false)
			#expect(session.chatHistoryMessageIsDuplicate(noTime) == false)
		}
	}

	@Test("A read marker at the newest line clears the unread counts, and a star does not")
	func receivedReadMarkerAtNewestLineClearsUnreadCounts() throws {
		let session = makeHistorySession()
		session.enableCapability(.readMarker)

		try withChannel(named: "#chat", on: session) { channel in
			let date = Date(timeIntervalSince1970: 1_700_000_000)

			index(chatLine(messageIdentifier: "r1", nickname: "a", text: "hi", date: date), for: channel)
			channel.unreadCount = 3
			channel.nicknameHighlightCount = 1

			let olderMarker = try message(
				":irc.example.net MARKREAD #chat timestamp=2023-11-14T22:13:19.000Z",
				on: session
			)
			let newestMarker = try message(
				":irc.example.net MARKREAD #chat timestamp=2023-11-14T22:13:20.000Z",
				on: session
			)
			let starMarker = try message(":irc.example.net MARKREAD #chat *", on: session)

			session.receiveReadMarker(olderMarker)

			#expect(channel.unreadCount == 3)
			#expect(channel.nicknameHighlightCount == 1)

			session.receiveReadMarker(newestMarker)

			#expect(channel.unreadCount == 0)
			#expect(channel.nicknameHighlightCount == 0)
			#expect(channel.isUnread == false)

			channel.unreadCount = 1
			session.receiveReadMarker(starMarker)

			#expect(channel.unreadCount == 1)
		}
	}

	@Test("A pending read marker cannot acknowledge a later unseen message")
	func pendingReadMarkerCapturesViewedDate() throws {
		let session = makeHistorySession()
		session.enableCapability(.readMarker)
		try withChannel(named: "#chat", on: session) { channel in
			let date = Date(timeIntervalSince1970: 1_700_000_000)
			index(chatLine(messageIdentifier: "seen", nickname: "a", text: "seen", date: date), for: channel)
			session.markConversation(asRead: channel)
			index(chatLine(messageIdentifier: "unseen", nickname: "a", text: "unseen",
			               date: date.addingTimeInterval(5)), for: channel)
			session.onReadMarkerTimer()
			#expect(sentLines(of: session) == ["MARKREAD #chat timestamp=2023-11-14T22:13:20.000Z"])
		}
	}

	@Test("A read marker is sent once for each newest line, not once per request")
	func readMarkerIsSentOncePerNewestLine() throws {
		let session = makeHistorySession()
		session.enableCapability(.readMarker)

		try withChannel(named: "#chat", on: session) { channel in
			session.markConversation(asRead: channel)
			session.onReadMarkerTimer()
			#expect(session.sentLines.count == 0)

			let date = Date(timeIntervalSince1970: 1_700_000_000)
			index(chatLine(messageIdentifier: "r1", nickname: "a", text: "hi", date: date), for: channel)

			session.markConversation(asRead: channel)
			session.markConversation(asRead: channel)
			session.onReadMarkerTimer()

			#expect(sentLines(of: session) == ["MARKREAD #chat timestamp=2023-11-14T22:13:20.000Z"])

			session.markConversation(asRead: channel)
			session.onReadMarkerTimer()
			#expect(session.sentLines.count == 1)

			index(
				chatLine(messageIdentifier: "r2", nickname: "a", text: "again", date: date.addingTimeInterval(5)),
				for: channel
			)
			session.markConversation(asRead: channel)
			session.onReadMarkerTimer()

			#expect(sentLines(of: session).last == "MARKREAD #chat timestamp=2023-11-14T22:13:25.000Z")
			#expect(session.sentLines.count == 2)
		}
	}

	@Test("Selecting a channel asks for its history and its read marker")
	func readMarkerIsQueriedOnActivation() throws {
		let session = makeHistorySession()
		session.enableCapability(.readMarker)

		try withChannel(named: "#chat", on: session) { channel in
			session.noteConversationActivated(channel)

			#expect(sentLines(of: session) == ["CHATHISTORY LATEST #chat * 100", "MARKREAD #chat"])
		}
	}

	@Test("No read marker is sent without the capability")
	func readMarkerIsNotSentWithoutTheCapability() throws {
		let session = makeHistorySession()

		try withChannel(named: "#chat", on: session) { channel in
			index(chatLine(messageIdentifier: "r1", nickname: "a", text: "hi", date: Date()), for: channel)
			session.sendReadMarker(for: channel, date: Date())

			#expect(session.sentLines.count == 0)
		}
	}

	@Test("With join and quit events hidden the netsplit still updates the member list")
	func netsplitSummaryIsHiddenWithJoinsAndQuits() throws {
		try withNetsplitSession(showingJoinsAndQuits: false) { session in
			try withChannel(named: "#chat", on: session) { channel in
				channel.activate()
				try feed([":alice!u@h JOIN #chat"], to: session)
				let linesBefore = session.printedLines.count

				try feed([
					":irc.example.net BATCH +ns netsplit irc.hub irc.leaf",
					"@batch=ns :alice!u@h QUIT :irc.hub irc.leaf",
					":irc.example.net BATCH -ns",
				], to: session)

				#expect(channel.memberExists("alice") == false)
				#expect(session.printedLines.count == linesBefore)
			}
		}
	}

	@Test("A collapsed channel keeps admitted events when global events are off")
	func collapsedChannelKeepsEventsWithGlobalEventsOff() throws {
		try withNetsplitSession(showingJoinsAndQuits: false) { session in
			session.config.ignoreList = [AddressBookEntry.newIgnoreEntry(forHostmask: "bob!*@*")]
			try withChannel(named: "#chat", on: session) { channel in
				var config = channel.config
				config.generalEventMessageDisplay = .collapse
				channel.updateConfig(config)
				channel.activate()
				let linesBeforeJoin = session.printedLines.count
				try feed([":alice!u@h JOIN #chat", ":bob!u@h JOIN #chat"], to: session)

				#expect(session.printedLines.count == linesBeforeJoin + 1)
				let linesBeforeSplit = session.printedLines.count
				try feed([
					":irc.example.net BATCH +ns netsplit irc.hub irc.leaf",
					"@batch=ns :alice!u@h QUIT :irc.hub irc.leaf",
					"@batch=ns :bob!u@h QUIT :irc.hub irc.leaf",
					":irc.example.net BATCH -ns",
				], to: session)

				let newLines = printedLines(from: linesBeforeSplit, on: session)
				#expect(newLines.count == 1)
				#expect((newLines.first?["messageBody"] as? String)?.contains("alice") == true)
				#expect((newLines.first?["messageBody"] as? String)?.contains("bob") == false)
				#expect(channel.memberExists("alice") == false)
				#expect(channel.memberExists("bob") == false)
			}
		}
	}

	@Test("A netsplit batch prints one summary line and takes its users out of the channel")
	func netsplitBatchProducesOneSummaryLineAndUpdatesMembers() throws {
		try withNetsplitSession(showingJoinsAndQuits: true) { session in
			try withChannel(named: "#chat", on: session) { channel in
				channel.activate()

				try feed([
					":alice!u@h JOIN #chat",
					":bob!u@h JOIN #chat",
					":carol!u@h JOIN #chat",
				], to: session)

				#expect(channel.memberExists("alice"))
				#expect(channel.memberExists("bob"))
				#expect(channel.memberExists("carol"))

				var linesBefore = session.printedLines.count
				try feed([
					":irc.example.net BATCH +ns netsplit irc.hub irc.leaf",
					"@batch=ns :alice!u@h QUIT :irc.hub irc.leaf",
					"@batch=ns :bob!u@h QUIT :irc.hub irc.leaf",
					":irc.example.net BATCH -ns",
				], to: session)

				#expect(channel.memberExists("alice") == false)
				#expect(channel.memberExists("bob") == false)
				#expect(channel.memberExists("carol"))

				var newLines = printedLines(from: linesBefore, on: session)
				#expect(newLines.count == 1)
				#expect(
					newLines.first?["messageBody"] as? String
						== "Netsplit between \u{2}irc.hub\u{2} and \u{2}irc.leaf\u{2}: 2 users left (alice, bob)"
				)
				#expect((newLines.first?["lineType"] as? NSNumber)?.uintValue == ChatLineKind.quit.rawValue)
				#expect(newLines.first?["channel"] as? Conversation === channel)

				linesBefore = session.printedLines.count
				try feed([
					":irc.example.net BATCH +nj netjoin irc.hub irc.leaf",
					"@batch=nj :alice!u@h JOIN #chat",
					"@batch=nj :bob!u@h JOIN #chat",
					":irc.example.net BATCH -nj",
				], to: session)

				#expect(channel.memberExists("alice"))
				#expect(channel.memberExists("bob"))

				newLines = printedLines(from: linesBefore, on: session)
				#expect(newLines.count == 1)
				#expect(
					newLines.first?["messageBody"] as? String
						== "Netjoin between \u{2}irc.hub\u{2} and \u{2}irc.leaf\u{2}: 2 users rejoined (alice, bob)"
				)
				#expect((newLines.first?["lineType"] as? NSNumber)?.uintValue == ChatLineKind.join.rawValue)
			}
		}
	}

	@Test("A netsplit summary names ten users and counts the rest")
	func netsplitSummaryListsAtMostTenNicknames() throws {
		try withNetsplitSession(showingJoinsAndQuits: true) { session in
			try withChannel(named: "#chat", on: session) { channel in
				channel.activate()

				let joins = (1 ... 12).map { ":user\($0)!u@h JOIN #chat" }
				var quits = [":irc.example.net BATCH +ns netsplit irc.hub irc.leaf"]
				quits.append(contentsOf: (1 ... 12).map { "@batch=ns :user\($0)!u@h QUIT :split" })
				quits.append(":irc.example.net BATCH -ns")

				try feed(joins, to: session)
				let linesBefore = session.printedLines.count
				try feed(quits, to: session)

				#expect(session.printedLines.count == linesBefore + 1)
				#expect(
					(session.printedLines.lastObject as? [String: Any])?["messageBody"] as? String
						== "Netsplit between \u{2}irc.hub\u{2} and \u{2}irc.leaf\u{2}: 12 users left " +
						"(user1, user2, user3, user4, user5, user6, user7, user8, user9, user10, … and 2 more)"
				)
				#expect(channel.memberExists("user1") == false)
				#expect(channel.memberExists("user12") == false)
			}
		}
	}
}
