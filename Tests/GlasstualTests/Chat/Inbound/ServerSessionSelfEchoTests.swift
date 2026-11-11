// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing

/** With `echo-message` and no label to match the echo against, the server's copy
 of an outgoing message is the only one printed. Credentials in it are masked
 the way a local print masks them, and the echo of a message the session chose
 not to print is not printed either. */
@MainActor
@Suite("Echoes of this session's own messages")
struct ServerSessionSelfEchoTests {
	private func makeSession(nicknamePassword: String? = nil) -> TestServerSession {
		let session = TestServerSession(configDictionary: ["nickname": "me"], nicknamePassword: nicknamePassword)
		session.userNickname = "me"
		session.userHostmask = "me!u@h"
		session.setConnectionTransportForTesting(.connected)
		session.markAsLoggedIn()
		session.forwardsProcessedMessages = true
		session.enableCapability(.echoMessage)
		return session
	}

	private func receive(_ line: String, on session: TestServerSession, replayed: Bool = false) throws {
		var message = try #require(Message(line: line, on: session))
		message.isReplayed = replayed
		session.processIncomingMessage(message)
	}

	private func printedBodies(of session: TestServerSession) -> [String] {
		session.printedLines.compactMap { ($0 as? [String: Any])?["messageBody"] as? String }
	}

	private func sentLines(of session: TestServerSession) -> [String] {
		session.sentLines.compactMap { $0 as? String }
	}

	@Test("A self echo to NickServ prints with the password masked, in the NickServ query")
	func identifyEchoIsMasked() throws {
		let session = makeSession()

		try receive(":me!u@h PRIVMSG NickServ :IDENTIFY hunter2", on: session)

		let line = try #require(session.printedLines.firstObject as? [String: Any])
		#expect(line["messageBody"] as? String == "IDENTIFY ••••••")
		#expect((line["channel"] as? Conversation)?.name == "NickServ")
		#expect(printedBodies(of: session).allSatisfy { $0.contains("hunter2") == false })
	}

	@Test("A self NOTICE to NickServ prints with the password masked")
	func identifyNoticeEchoIsMasked() throws {
		let session = makeSession()

		try receive(":me!u@h NOTICE NickServ :IDENTIFY hunter2", on: session)

		#expect(printedBodies(of: session) == ["IDENTIFY ••••••"])
	}

	@Test("A replayed self IDENTIFY prints masked")
	func replayedIdentifyIsMasked() throws {
		let session = makeSession()

		try receive(":me!u@h PRIVMSG NickServ :IDENTIFY hunter2", on: session, replayed: true)

		#expect(printedBodies(of: session) == ["IDENTIFY ••••••"])
	}

	@Test("Text echoed to a channel is never rewritten")
	func channelTextIsNotMasked() throws {
		let session = makeSession()
		_ = try #require(session.findConversationOrCreate("#chanserv"))

		try receive(":me!u@h PRIVMSG #chanserv :IDENTIFY hunter2", on: session)

		#expect(printedBodies(of: session) == ["IDENTIFY hunter2"])
	}

	@Test("The echo of /smsg prints nothing and opens no query")
	func secretMessageEchoIsDropped() throws {
		let session = makeSession()

		session.sendCommand("smsg NickServ IDENTIFY x", completeTarget: false, target: nil)
		#expect(sentLines(of: session) == ["PRIVMSG NickServ :IDENTIFY x"])

		try receive(":me!u@h PRIVMSG NickServ :IDENTIFY x", on: session)

		#expect(session.printedLines.count == 0)
		#expect(session.findConversation("NickServ") == nil)
	}

	@Test("The echo of the identification sent for a NickServ notice prints nothing")
	func automaticIdentificationEchoIsDropped() throws {
		let session = makeSession(nicknamePassword: "hunter2")
		let notice = ":NickServ!NickServ@services. NOTICE me :This nickname is registered. "
			+ "Please choose a different nickname, or identify via /msg NickServ IDENTIFY me <password>"

		try receive(notice, on: session)
		#expect(sentLines(of: session).contains("PRIVMSG NickServ :IDENTIFY hunter2"))
		let printedBeforeEcho = session.printedLines.count

		try receive(":me!u@h PRIVMSG NickServ :IDENTIFY hunter2", on: session)

		#expect(session.printedLines.count == printedBeforeEcho)
		#expect(printedBodies(of: session).allSatisfy { $0.contains("hunter2") == false })
	}

	@Test("The echo of an ordinary /msg prints exactly once")
	func ordinaryMessageEchoPrintsOnce() throws {
		let session = makeSession()

		session.sendCommand("msg alice hello", completeTarget: false, target: nil)
		#expect(session.printedLines.count == 0)

		try receive(":me!u@h PRIVMSG alice :hello", on: session)

		#expect(printedBodies(of: session) == ["hello"])
		#expect(session.findConversation("alice") != nil)
	}
}
