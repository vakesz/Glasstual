// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing

/// draft/extended-isupport: ISUPPORT before registration, and what a 005 that
/// lands before 001 may and may not do yet.
@MainActor
@Suite("draft/extended-isupport negotiation")
struct ExtendedISupportNegotiationTests {
	private func session() -> TestServerSession {
		let session = TestServerSession(configDictionary: ["nickname": "me", "username": "me"])
		session.setConnectionTransportForTesting(.connected)
		session.forwardsSentLines = true
		session.forwardsProcessedMessages = true
		return session
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

	private func sent(by session: TestServerSession) -> [String] {
		(session.sentLines as NSArray).compactMap { $0 as? String }
	}

	@Test("The acknowledgement sends ISUPPORT ahead of CAP END, once")
	func isupportGoesBeforeEnd() throws {
		let session = session()
		defer { session.stopAllTimers() }

		try feed([":irc.example.net CAP * LS :draft/extended-isupport batch"], to: session)
		try feed([":irc.example.net CAP me ACK :batch draft/extended-isupport"], to: session)

		let lines = sent(by: session)
		let isupport = try #require(lines.firstIndex(of: "ISUPPORT"))
		let end = try #require(lines.firstIndex(of: "CAP END"))
		#expect(isupport < end)

		try feed([":irc.example.net CAP me ACK :draft/extended-isupport"], to: session)
		#expect(sent(by: session).count { $0 == "ISUPPORT" } == 1)
	}

	@Test("After registration the acknowledgement asks for nothing")
	func noRequestAfterRegistration() throws {
		let session = session()
		session.markAsLoggedIn()

		try feed([":irc.example.net CAP * NEW :draft/extended-isupport"], to: session)
		try feed([":irc.example.net CAP me ACK :draft/extended-isupport"], to: session)

		#expect(sent(by: session).contains("ISUPPORT") == false)
	}

	@Test("A 005 before 001 sets the casemapping and the socket's line budget")
	func preRegistrationTokensApply() throws {
		let session = session()

		try feed([":irc.example.net 005 * CASEMAPPING=ascii LINELEN=1024 :are supported by this server"], to: session)

		#expect(session.supportInfo.caseMapping == .ascii)
		#expect(session.supportInfo.maximumLineLength == 1024)
		#expect(session.isLoggedIn == false)
	}

	@Test("MONITOR and PROTOCTL wait for 001")
	func presenceAndLegacyWaitForRegistration() throws {
		let session = session()
		defer { session.stopAllTimers() }
		let query = try #require(session.findConversationOrCreate("bob", isDirect: true))
		_ = query

		try feed([":irc.example.net 005 * MONITOR=100 NAMESX :are supported by this server"], to: session)

		#expect(sent(by: session).contains { $0.hasPrefix("MONITOR") } == false)
		#expect(sent(by: session).contains("PROTOCTL NAMESX") == false)

		try feed([":irc.example.net 001 me :Welcome"], to: session)

		#expect(sent(by: session).contains("PROTOCTL NAMESX"))
		#expect(sent(by: session).contains { $0.hasPrefix("MONITOR + ") && $0.contains("bob") })
	}
}

/// A `draft/isupport` batch holds one RPL_ISUPPORT list over several lines.
@MainActor
@Suite("ISUPPORT batches")
struct ISupportBatchTests {
	private func session() -> TestServerSession {
		let session = TestServerSession(configDictionary: ["nickname": "me", "username": "me"])
		session.setConnectionTransportForTesting(.connected)
		session.enableCapability(.batch)
		session.enableCapability(.extendedISupport)
		session.forwardsProcessedMessages = true
		return session
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

	private func consoleLines(of session: TestServerSession) -> [[String: Any]] {
		(session.printedLines as NSArray).compactMap { $0 as? [String: Any] }.filter { ($0["command"] as? String) == "005" }
	}

	@Test("Every line of the batch applies, as one update with one console line")
	func batchAppliesTogether() throws {
		let session = session()

		try feed([
			":irc.example.net BATCH +i draft/isupport",
			"@batch=i :irc.example.net 005 * NETWORK=Example :are supported",
			"@batch=i :irc.example.net PRIVMSG me :not allowed here",
			"@batch=i :irc.example.net 005 * CASEMAPPING=ascii :are supported",
			"@batch=i :irc.example.net 005 * LINELEN=1024 :are supported",
		], to: session)
		#expect(session.supportInfo.networkName == nil)

		try feed([":irc.example.net BATCH -i"], to: session)

		#expect(session.supportInfo.networkName == "Example")
		#expect(session.supportInfo.caseMapping == .ascii)
		#expect(session.supportInfo.maximumLineLength == 1024)
		#expect(consoleLines(of: session).count <= 1)
		#expect(session.processedMessages.contains { $0.command == "PRIVMSG" } == false)
	}

	@Test("A later batch removes a token")
	func laterBatchRemovesToken() throws {
		let session = session()

		try feed([
			":irc.example.net BATCH +a draft/isupport",
			"@batch=a :irc.example.net 005 * NETWORK=Example :are supported",
			":irc.example.net BATCH -a",
			":irc.example.net BATCH +b draft/isupport",
			"@batch=b :irc.example.net 005 * -NETWORK :are supported",
			":irc.example.net BATCH -b",
		], to: session)

		#expect(session.supportInfo.networkName == nil)
	}
}
