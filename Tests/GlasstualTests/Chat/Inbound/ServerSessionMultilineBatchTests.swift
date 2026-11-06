// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing

/// `draft/multiline` batches reach the rest of the session as one message,
/// wherever they sit in the batch family.
@MainActor
@Suite("Multi-line batches", .serialized)
struct ServerSessionMultilineBatchTests {
	private func session() -> TestServerSession {
		let session = TestServerSession(configDictionary: ["nickname": "me", "username": "me"])
		session.userNickname = "me"
		session.enableCapability(.batch)
		session.enableCapability(.messageTags)
		session.enableCapability(.multiline)
		session.isLoggedIn = true
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

	@Test("The lines of a batch arrive as one message")
	func linesArriveAsOneMessage() throws {
		let session = session()

		try feed([
			":alice!u@h BATCH +m draft/multiline #chan",
			"@batch=m :alice!u@h PRIVMSG #chan :one",
			"@batch=m :alice!u@h PRIVMSG #chan :two",
			":alice!u@h BATCH -m",
		], to: session)

		#expect(session.processedMessages.count == 1)
		#expect(session.processedMessages.first?.params == ["#chan", "one\ntwo"])
	}

	@Test("Nothing is delivered before the batch closes")
	func nothingBeforeTheBatchCloses() throws {
		let session = session()

		try feed([
			":alice!u@h BATCH +m draft/multiline #chan",
			"@batch=m :alice!u@h PRIVMSG #chan :one",
			"@batch=m :alice!u@h PRIVMSG #chan :two",
		], to: session)

		#expect(session.processedMessages.isEmpty)
	}

	@Test("A concat line joins the one before it with nothing between")
	func concatLinesJoin() throws {
		let session = session()

		try feed([
			":alice!u@h BATCH +m draft/multiline #chan",
			"@batch=m :alice!u@h PRIVMSG #chan :a long ",
			"@batch=m;draft/multiline-concat :alice!u@h PRIVMSG #chan :line",
			"@batch=m :alice!u@h PRIVMSG #chan :next",
			":alice!u@h BATCH -m",
		], to: session)

		#expect(session.processedMessages.map { $0.params[1] } == ["a long line\nnext"])
	}

	@Test("The message carries the identifier its batch was opened with")
	func identifierComesFromTheOpeningLine() throws {
		let session = session()

		try feed([
			"@msgid=abc123 :alice!u@h BATCH +m draft/multiline #chan",
			"@batch=m :alice!u@h PRIVMSG #chan :one",
			"@batch=m :alice!u@h PRIVMSG #chan :two",
			":alice!u@h BATCH -m",
		], to: session)

		#expect(session.processedMessages.first?.messageIdentifier == "abc123")
	}

	@Test("A batch inside another batch is still one message")
	func nestedBatchIsOneMessage() throws {
		let session = session()

		try feed([
			":srv BATCH +o labeled-response",
			"@batch=o :alice!u@h BATCH +m draft/multiline #chan",
			"@batch=m :alice!u@h PRIVMSG #chan :one",
			"@batch=m :alice!u@h PRIVMSG #chan :two",
			"@batch=o :alice!u@h BATCH -m",
			":srv BATCH -o",
		], to: session)

		#expect(session.processedMessages.count == 1)
		#expect(session.processedMessages.first?.params == ["#chan", "one\ntwo"])
	}

	@Test("A batch inside a chat history page is one replayed message")
	func historyPageHoldsOneMessage() throws {
		let session = session()
		session.enableCapability(.serverTime)
		session.enableCapability(.chatHistory)

		try feed([
			":srv BATCH +h chathistory #chan",
			"@batch=h :alice!u@h BATCH +m draft/multiline #chan",
			"@batch=m :alice!u@h PRIVMSG #chan :one",
			"@batch=m :alice!u@h PRIVMSG #chan :two",
			"@batch=h :alice!u@h BATCH -m",
			"@batch=h :bob!u@h PRIVMSG #chan :after",
			":srv BATCH -h",
		], to: session)

		#expect(session.processedMessages.map { $0.params[1] } == ["one\ntwo", "after"])
		let allReplayed = session.processedMessages.allSatisfy(\.isReplayed)
		#expect(allReplayed)
	}

	@Test("A labelled echo settles its delivery once, as one message")
	func echoSettlesTheDeliveryOnce() throws {
		let session = session()
		session.enableCapability(.labeledResponse)
		session.enableCapability(.echoMessage)
		session.forwardsProcessedMessages = true
		let channel = try #require(session.findConversationOrCreate("#chan"))
		channel.activate()
		let label = try #require(session.registerPendingDelivery(for: channel))
		#expect(session.deliveryState(forLabel: label) == .pending)

		try feed([
			"@label=\(label) :me!u@h BATCH +r draft/multiline #chan",
			"@batch=r :me!u@h PRIVMSG #chan :one",
			"@batch=r :me!u@h PRIVMSG #chan :two",
			":me!u@h BATCH -r",
		], to: session)

		#expect(session.deliveryState(forLabel: label) != .pending)
		#expect(session.processedMessages.count == 1)
	}
}
