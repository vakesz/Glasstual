// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing

@Suite("Chat history targets")
struct ChatHistoryTargetsPolicyTests {
	private let date = Date(timeIntervalSince1970: 1_793_260_800)

	private func targets(_ names: [String]) -> [ChatHistoryTarget] {
		names.map { ChatHistoryTarget(name: $0, latest: date) }
	}

	@Test("Channels, the user, ignored senders and open conversations are left out, in the server's order")
	func filtersAndKeepsOrder() {
		let found = ChatHistoryTargetsPolicy.discovered(
			targets(["carol", "#chan", "me", "spammer", "bob", "alice", "Carol"]),
			isChannel: { $0.hasPrefix("#") },
			isSelf: { $0 == "me" },
			isIgnored: { $0 == "spammer" },
			hasConversation: { $0 == "bob" },
			cap: 20
		)
		#expect(found.open == ["carol", "alice"])
		#expect(found.overflow.isEmpty)
	}

	@Test("The cap splits what is opened from what is listed")
	func capSplits() {
		let found = ChatHistoryTargetsPolicy.discovered(
			targets(["a", "b", "c"]),
			isChannel: { _ in false }, isSelf: { _ in false }, isIgnored: { _ in false }, hasConversation: { _ in false },
			cap: 2
		)
		#expect(found.open == ["a", "b"])
		#expect(found.overflow == ["c"])
	}

	@Test("A TARGETS line is read; anything else is not", arguments: [
		(["TARGETS", "bob", "timestamp=2026-10-29T08:00:00.000Z"], true),
		(["TARGETS", "bob", "2026-10-29T08:00:00.000Z"], false),
		(["TARGETS", "bob", "timestamp=yesterday"], false),
		(["TARGETS", "bob"], false),
		(["LATEST", "bob", "timestamp=2026-10-29T08:00:00.000Z"], false),
	])
	func lineParsing(_ parameters: [String], _ isRead: Bool) {
		#expect((ChatHistoryTarget(parameters: parameters) != nil) == isRead)
	}
}

/// The sweep after registration that opens missed direct conversations.
@MainActor
@Suite("Chat history targets on a session")
struct ServerSessionChatHistoryTargetsTests {
	private func session(lastSeen: TimeInterval = 1_793_000_000, settings: ChatSettings = .current()) -> TestServerSession {
		let session = TestServerSession(
			configDictionary: ["nickname": "me", "lastMessageServerTime": lastSeen],
			nicknamePassword: nil,
			fixture: ChatEnvironmentFixture(settings: settings)
		)
		session.userNickname = "me"
		session.setConnectionTransportForTesting(.connected)
		session.enableCapability([.batch, .serverTime, .messageTags, .labeledResponse, .chatHistory])
		session.isLoggedIn = true
		session.forwardsProcessedMessages = true
		return session
	}

	private func sent(by session: TestServerSession) -> [String] {
		(session.sentLines as NSArray).compactMap { $0 as? String }
	}

	private func printed(by session: TestServerSession) -> [String] {
		(session.printedLines as NSArray).compactMap { ($0 as? [String: Any])?["messageBody"] as? String }
	}

	private func feed(_ lines: [String], to session: TestServerSession) throws {
		for line in lines {
			let message = try #require(Message(line: line, on: session))
			if session.filterBatchCommandIncomingData(message) {
				continue
			}
			if message.command == "BATCH" {
				session.receiveBatch(message)
			} else {
				session.processIncomingMessage(message)
			}
		}
	}

	private func label(_ session: TestServerSession) throws -> String {
		let line = try #require(sent(by: session).last)
		return try #require(line.split(separator: " ").first.map { String($0.dropFirst("@label=".count)) })
	}

	@Test("The request names the newer bound first, both moved out, and is labelled")
	func requestShape() throws {
		let session = session()
		defer { session.stopAllTimers() }
		let since = Date(timeIntervalSince1970: 1_793_000_000)

		#expect(session.requestChatHistoryTargets(since: since, reason: .automatic))

		let line = try #require(sent(by: session).last)
		let parts = line.split(separator: " ").map(String.init)
		#expect(parts.first?.hasPrefix("@label=targets-") == true)
		#expect(Array(parts.dropFirst().prefix(2)) == ["CHATHISTORY", "TARGETS"])
		#expect(parts.last == "50")
		let from = try #require(DateFormatting.date(fromISO8601: String(parts[3].dropFirst("timestamp=".count))))
		let to = try #require(DateFormatting.date(fromISO8601: String(parts[4].dropFirst("timestamp=".count))))
		#expect(from > to)
		#expect(to == since.addingTimeInterval(-5))
		#expect(session.requestChatHistoryTargets(since: since, reason: .automatic) == false)
	}

	@Test("The sweep applies only with the settings on, a last-seen time, and a bound connection")
	func sweepConditions() {
		#expect(session().discoversMissedDirectMessages)
		#expect(session(lastSeen: 0).discoversMissedDirectMessages == false)

		var off = ChatSettings.current()
		off.discoverMissedDirectMessages = false
		#expect(session(settings: off).discoversMissedDirectMessages == false)

		let bouncer = session()
		bouncer.enableCapability(.bouncerNetworks)
		#expect(bouncer.discoversMissedDirectMessages == false)
	}

	@Test("The batch asks for the latest page of new direct names only, and lists the rest")
	func batchAsksForNewNames() throws {
		let session = session()
		defer { session.stopAllTimers() }
		_ = session.findConversationOrCreate("known", isDirect: true)
		session.sentLines.removeAllObjects()
		session.requestChatHistoryTargets(since: Date(timeIntervalSince1970: 1_793_000_000), reason: .automatic)
		let label = try label(session)
		var lines = ["@label=\(label) :irc.example.net BATCH +t draft/chathistory-targets"]
		let names = ["#chan", "known", "me", "broken"] + (1 ... 21).map { "user\($0)" }
		for name in names {
			let stamp = name == "broken" ? "nonsense" : "timestamp=2026-10-29T08:00:00.000Z"
			lines.append("@batch=t :irc.example.net CHATHISTORY TARGETS \(name) \(stamp)")
		}
		lines.append(":irc.example.net BATCH -t")

		try feed(lines, to: session)

		let requests = sent(by: session).filter { $0.hasPrefix("CHATHISTORY LATEST ") }
		#expect(requests.count == 20)
		#expect(requests.first == "CHATHISTORY LATEST user1 * 100")
		#expect(requests.contains { $0.contains(" user21 ") || $0.contains("#chan") || $0.contains(" known ") } == false)
		#expect(session.findConversation("user1") == nil)
		#expect(printed(by: session).last == String(localized: .ChatHistory.chatHistoryTargetsOverflow("user21")))
		#expect(session.chatHistory.targetsSweep == nil)
	}

	/// A rule on the host cannot be judged from a nickname, so the page is
	/// asked for and the rule is applied to its messages.
	@Test("A conversation opens, unselected, only for messages that pass the ignore rules")
	func ignoreRulesJudgeTheMessages() throws {
		let session = session()
		defer { session.stopAllTimers() }
		session.config.ignoreList = [AddressBookEntry.newIgnoreEntry(forHostmask: "*!*@spam.example")]
		session.requestChatHistoryTargets(since: Date(timeIntervalSince1970: 1_793_000_000), reason: .automatic)
		try feed([
			"@label=\(label(session)) :irc.example.net BATCH +t draft/chathistory-targets",
			"@batch=t :irc.example.net CHATHISTORY TARGETS alice timestamp=2026-10-29T08:00:00.000Z",
			"@batch=t :irc.example.net CHATHISTORY TARGETS spammer timestamp=2026-10-29T08:00:00.000Z",
			":irc.example.net BATCH -t",
		], to: session)
		#expect(sent(by: session).contains("CHATHISTORY LATEST spammer * 100"))

		try feed([
			":irc.example.net BATCH +a chathistory alice",
			"@batch=a;msgid=a1;time=2026-10-29T08:00:00.000Z :alice!u@friendly.example PRIVMSG me :hello",
			":irc.example.net BATCH -a",
			":irc.example.net BATCH +s chathistory spammer",
			"@batch=s;msgid=s1;time=2026-10-29T08:00:00.000Z :spammer!u@spam.example PRIVMSG me :buy now",
			":irc.example.net BATCH -s",
		], to: session)

		#expect(session.findConversation("alice")?.isDirect == true)
		#expect(session.findConversation("spammer") == nil)
		#expect(session.recordedOutput.selectedConversation == nil)
	}

	@Test("A FAIL ends the sweep, and it is not tried again on this connection")
	func failureStopsTheSweep() throws {
		let session = session()
		defer { session.stopAllTimers() }
		session.requestChatHistoryTargets(since: Date(timeIntervalSince1970: 1_793_000_000), reason: .automatic)
		let label = try label(session)

		try session.receiveStandardReply(#require(Message(
			line: "@label=\(label) :irc.example.net FAIL CHATHISTORY INVALID_PARAMS TARGETS :Not supported",
			on: session
		)))

		#expect(session.chatHistory.targetsSweep == nil)
		#expect(session.discoversMissedDirectMessages == false)
	}

	@Test("/chathistory targets lists what it found and fetches it")
	func commandListsTargets() throws {
		let session = session()
		defer { session.stopAllTimers() }

		session.sendCommand("chathistory targets 24h", completeTarget: false)
		let label = try label(session)
		try feed([
			"@label=\(label) :irc.example.net BATCH +t draft/chathistory-targets",
			"@batch=t :irc.example.net CHATHISTORY TARGETS alice timestamp=2026-10-29T08:00:00.000Z",
			":irc.example.net BATCH -t",
		], to: session)

		#expect(sent(by: session).contains("CHATHISTORY LATEST alice * 100"))
		#expect(printed(by: session).contains { $0.hasPrefix("alice") })
		#expect(printed(by: session).last == String(localized: .ChatHistory.chatHistoryTargetsOpened(1)))
	}
}
