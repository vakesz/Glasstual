// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing

/// `CHATHISTORY AROUND`: the page around one message, fetched for the
/// transcript and stored rather than drawn.
@MainActor
@Suite("Message context from the server", .timeLimit(.minutes(1)))
struct ServerSessionMessageContextTests {
	private func session(isupport: String? = nil) throws -> (TestServerSession, Conversation) {
		let session = TestServerSession()
		session.setConnectionTransportForTesting(.connected)
		session.enableCapability([.batch, .serverTime, .messageTags, .labeledResponse])
		session.isLoggedIn = true
		session.forwardsProcessedMessages = true
		session.linePrintObserver = nil
		if let isupport {
			session.supportInfo.processConfigurationData(isupport)
		}
		let channel = try #require(session.findConversationOrCreate("#chat"))
		channel.activate()
		session.enableCapability(.chatHistory)
		session.sentLines.removeAllObjects()
		return (session, channel)
	}

	private func sent(by session: TestServerSession) -> [String] {
		(session.sentLines as NSArray).compactMap { $0 as? String }
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

	private func requestLabel(_ session: TestServerSession) async throws -> String {
		try await Eventually.until("the request") { sent(by: session).isEmpty == false }
		let line = try #require(sent(by: session).last)
		#expect(line.hasSuffix("CHATHISTORY AROUND #chat msgid=xyz 100"))
		return try #require(line.split(separator: " ").first.map { String($0.dropFirst("@label=".count)) })
	}

	@Test("The page around the message is asked for, labelled, and its arrival reported")
	func pageArrives() async throws {
		let (session, channel) = try session()
		defer { session.stopAllTimers() }

		let request = Task { await session.requestMessageContext(identifier: "xyz", in: channel) }
		let label = try await requestLabel(session)
		try feed([
			"@label=\(label) :irc.example.net BATCH +a chathistory #chat",
			"@batch=a;msgid=xyz;time=2026-11-01T00:00:00.000Z :bob!u@h PRIVMSG #chat :original",
			":irc.example.net BATCH -a",
		], to: session)

		#expect(await request.value)
		#expect(session.chatHistory.paging.isEmpty)
	}

	@Test("A FAIL reports the message as not found")
	func failureReportsFalse() async throws {
		let (session, channel) = try session()
		defer { session.stopAllTimers() }

		let request = Task { await session.requestMessageContext(identifier: "xyz", in: channel) }
		let label = try await requestLabel(session)
		try feed(["@label=\(label) :irc.example.net FAIL CHATHISTORY INVALID_TARGET AROUND #chat :No"], to: session)

		#expect(await request.value == false)
	}

	@Test("A disconnect reports the message as not found")
	func resetReportsFalse() async throws {
		let (session, channel) = try session()
		defer { session.stopAllTimers() }

		let request = Task { await session.requestMessageContext(identifier: "xyz", in: channel) }
		_ = try await requestLabel(session)
		session.resetChatHistoryState()

		#expect(await request.value == false)
	}

	@Test("A server that takes only timestamps is not asked")
	func timestampOnlyServerIsNotAsked() async throws {
		let (session, channel) = try session(isupport: "MSGREFTYPES=timestamp")

		#expect(await session.requestMessageContext(identifier: "xyz", in: channel) == false)
		#expect(sent(by: session).isEmpty)
	}
}
