// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing

/** A message to `@#channel` reached only the channel's operators. It is filed in
 the channel like any other, and the printed line keeps the target, so the
 reader can tell it apart from a message everyone in the channel saw. */
@MainActor
@Suite("STATUSMSG lines")
struct ServerSessionStatusMessageTests {
	private func makeSession() throws -> (TestServerSession, Conversation) {
		let session = TestServerSession(configDictionary: ["nickname": "me"])
		session.userNickname = "me"
		session.setConnectionTransportForTesting(.connected)
		session.markAsLoggedIn()
		session.forwardsProcessedMessages = true
		session.supportInfo.processConfigurationData("STATUSMSG=@+ PREFIX=(ov)@+")
		let channel = try #require(session.findConversationOrCreate("#staff"))
		channel.activate()
		return (session, channel)
	}

	private func receive(_ line: String, on session: TestServerSession) throws {
		try session.processIncomingMessage(#require(Message(line: line, on: session)))
	}

	private func printedLine(of session: TestServerSession) throws -> [String: Any] {
		try #require(session.printedLines.lastObject as? [String: Any])
	}

	@Test("A message to @#staff prints in #staff and keeps its target")
	func statusMessageKeepsTarget() throws {
		let (session, channel) = try makeSession()

		try receive(":alice!u@h PRIVMSG @#staff :ops only", on: session)

		let line = try printedLine(of: session)
		#expect(line["channel"] as? Conversation === channel)
		#expect(line["statusMessageTarget"] as? String == "@#staff")
	}

	@Test("A message to the whole channel carries no target")
	func publicMessageHasNoTarget() throws {
		let (session, channel) = try makeSession()

		try receive(":alice!u@h PRIVMSG #staff :everyone", on: session)

		let line = try printedLine(of: session)
		#expect(line["channel"] as? Conversation === channel)
		#expect(line["statusMessageTarget"] == nil)
	}

	@Test("A local /omsg print carries the prefixed target")
	func operatorMessagePrintCarriesTarget() throws {
		let (session, channel) = try makeSession()

		session.sendCommand("omsg #staff ops only", completeTarget: false, target: nil)

		#expect(session.sentLines.compactMap { $0 as? String } == ["PRIVMSG @#staff :ops only"])
		let line = try printedLine(of: session)
		#expect(line["channel"] as? Conversation === channel)
		#expect(line["statusMessageTarget"] as? String == "@#staff")
	}
}
