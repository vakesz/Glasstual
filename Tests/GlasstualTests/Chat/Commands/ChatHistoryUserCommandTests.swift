// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing

@MainActor
@Suite("/chathistory")
struct ChatHistoryUserCommandTests {
	private nonisolated static let date = Date(timeIntervalSince1970: 1_793_260_800)
	private nonisolated static let now = Date(timeIntervalSince1970: 1_793_347_200)
	private nonisolated static let midnight = Date(timeIntervalSince1970: 1_793_232_000)

	private func parse(_ line: String) throws(ChatHistoryUserCommand.ParseError) -> ChatHistoryUserCommand {
		try ChatHistoryUserCommand(CommandArguments(line), isTarget: { $0.hasPrefix("#") || $0 == "bob" }, now: Self.now)
	}

	@Test("Lines are read into requests", arguments: [
		("latest", ChatHistoryUserCommand.latest(target: nil, after: .unbounded, limit: nil)),
		("latest #c * 20", .latest(target: "#c", after: .unbounded, limit: 20)),
		("before msgid=abc", .before(target: nil, .messageIdentifier("abc"), limit: nil)),
		("after bob 2026-10-29T08:00:00Z 5", .after(target: "bob", .timestamp(date), limit: 5)),
		("after 2026-10-29", .after(target: nil, .timestamp(midnight), limit: nil)),
		("around xyz", .around(target: nil, .messageIdentifier("xyz"), limit: nil)),
		(
			"between #c msgid=a timestamp=2026-10-29T08:00:00.000Z",
			.between(target: "#c", .messageIdentifier("a"), .timestamp(date), limit: nil)
		),
		("targets", .targets(since: nil, limit: nil)),
		("targets 24h 10", .targets(since: now.addingTimeInterval(-86400), limit: 10)),
		("targets 2026-10-29", .targets(since: midnight, limit: nil)),
		("fill", .fill(target: nil)),
		("FILL #c", .fill(target: "#c")),
	])
	func parsing(_ line: String, _ expected: ChatHistoryUserCommand) throws {
		#expect(try parse(line) == expected)
	}

	@Test("Bad lines say what is wrong", arguments: [
		("", ChatHistoryUserCommand.ParseError.missingSubcommand),
		("frobnicate #c", .unknownSubcommand("frobnicate")),
		("before", .missingReference),
		("between msgid=a", .missingReference),
		("after nonsense", .invalidReference("nonsense")),
		("targets yesterday", .invalidReference("yesterday")),
	])
	func errors(_ line: String, _ expected: ChatHistoryUserCommand.ParseError) {
		#expect(throws: expected) { try parse(line) }
	}

	private func session() throws -> (TestServerSession, Conversation) {
		let session = TestServerSession()
		session.enableCapability(.batch)
		session.enableCapability(.serverTime)
		session.enableCapability(.messageTags)
		session.enableCapability(.labeledResponse)
		session.enableCapability(.chatHistory)
		session.isLoggedIn = true
		let channel = try #require(session.findConversationOrCreate("#chat"))
		channel.activate()
		session.sentLines.removeAllObjects()
		return (session, channel)
	}

	private func sent(by session: TestServerSession) -> [String] {
		(session.sentLines as NSArray).compactMap { $0 as? String }
	}

	@Test("The selected conversation is the default target")
	func defaultTarget() throws {
		let (session, _) = try session()

		session.sendCommand("chathistory after msgid=abc 10", completeTarget: true, target: "#chat")

		#expect(sent(by: session) == ["CHATHISTORY AFTER #chat msgid=abc 10"])
	}

	@Test("before goes out as a labelled scroll-back page")
	func beforeIsLabelled() throws {
		let (session, _) = try session()
		defer { session.stopAllTimers() }

		session.sendCommand("chathistory before msgid=abc", completeTarget: true, target: "#chat")

		let line = try #require(sent(by: session).first)
		#expect(line.hasPrefix("@label=history-"))
		#expect(line.hasSuffix("CHATHISTORY BEFORE #chat msgid=abc 100"))
	}

	@Test("INVALID_MSGREFTYPE asks for the same page by time, once")
	func invalidReferenceTypeRetriesWithTimestamp() throws {
		let (session, channel) = try session()
		defer { session.stopAllTimers() }
		let request = ServerHistoryRequest(id: UUID(), before: Self.date, oldestLineNumber: nil, messageIdentifier: "abc")
		#expect(session.requestServerHistory(request, in: channel))
		let first = try #require(sent(by: session).first)
		let label = try #require(first.split(separator: " ").first?.dropFirst("@label=".count)).description

		let failure = try #require(Message(
			line: "@label=\(label) :irc.example.net FAIL CHATHISTORY INVALID_MSGREFTYPE BEFORE #chat :msgid not supported",
			on: session
		))
		session.receiveStandardReply(failure)

		let retry = try #require(sent(by: session).last)
		#expect(sent(by: session).count == 2)
		#expect(retry.hasSuffix("CHATHISTORY BEFORE #chat timestamp=2026-10-29T08:00:00.000Z 100"))
		#expect(session.chatHistory.refusesMessageIdentifiers)
	}

	@Test("An unknown subcommand points at /quote")
	func unknownSubcommand() throws {
		let (session, _) = try session()

		session.sendCommand("chathistory frobnicate", completeTarget: true, target: "#chat")

		#expect(sent(by: session).isEmpty)
		let printed = (session.printedLines as NSArray).compactMap { ($0 as? [String: Any])?["messageBody"] as? String }
		#expect(printed.last == String(localized: .ChatHistory.chatHistoryUnknownSubcommand("frobnicate")))
	}
}
