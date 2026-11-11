// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing

/// Secure and unsupported DCC offers are declined in so many words, after the
/// checks every offer goes through, and nothing is opened for them.
@MainActor
@Suite("Secure DCC offer routing")
struct ServerSessionSecureDCCOfferTests {
	private func makeSession() -> TestServerSession {
		let session = TestServerSession(configDictionary: ["nickname": "me"])
		session.userNickname = "me"
		session.userHostmask = "me!u@h"
		session.markAsLoggedIn()
		session.forwardsProcessedMessages = true
		return session
	}

	private func offer(_ text: String, from sender: String = "alice", on session: TestServerSession, replayed: Bool = false) throws {
		var message = try #require(Message(line: ":\(sender)!a@example.test PRIVMSG me :\u{01}DCC \(text)\u{01}", on: session))
		message.isReplayed = replayed
		session.processIncomingMessage(message)
	}

	private func printedBodies(of session: TestServerSession) -> [String] {
		session.printedLines.compactMap { ($0 as? [String: Any])?["messageBody"] as? String }
	}

	@Test("A secure file offer is declined with its file named, in every form", arguments: [
		"SSEND file.txt 1568397154 5000 42",
		"SSEND file.txt 1568397154 0 42 T7",
		"ssend file.txt 1568397154 5000 42 7",
		"SSEND file.txt 3232235777 5000 42",
	])
	func secureFileOfferIsDeclined(text: String) throws {
		let session = makeSession()

		try offer(text, on: session)

		#expect(printedBodies(of: session) == [String(localized: .IRC.declinedSecureFileTransferOffer("alice", "file.txt"))])
		#expect(session.recordedOutput.presentedAlerts.isEmpty)
	}

	@Test("A secure chat offer is declined and opens nothing, in every form", arguments: [
		"SCHAT chat 1568397154 5000",
		"SCHAT chat 0 0 T9",
		"SCHAT chat 1568397154 5000 T9",
	])
	func secureChatOfferIsDeclined(text: String) throws {
		let session = makeSession()
		let conversationsBefore = session.conversationList.count

		try offer(text, on: session)

		#expect(printedBodies(of: session) == [String(localized: .IRC.declinedSecureDirectChatOffer("alice"))])
		#expect(session.recordedOutput.presentedAlerts.isEmpty)
		#expect(session.directChatConversation(forNickname: "alice") == nil)
		#expect(session.conversationList.count == conversationsBefore)
	}

	@Test("A turbo or reversed offer is declined by name", arguments: ["TSEND", "TSSEND", "STSEND", "SRECV"])
	func unsupportedOfferIsDeclined(verb: String) throws {
		let session = makeSession()

		try offer("\(verb) file.txt 1568397154 5000 42", on: session)

		#expect(printedBodies(of: session) == [String(localized: .IRC.declinedUnsupportedDccOffer("alice", verb))])
		#expect(session.recordedOutput.presentedAlerts.isEmpty)
	}

	@Test("A replayed secure offer is history: it is not declined, because it was never an offer")
	func replayedOfferIsNotDeclined() throws {
		let session = makeSession()

		try offer("SSEND file.txt 1568397154 5000 42", on: session, replayed: true)
		try offer("SCHAT chat 1568397154 5000", on: session, replayed: true)

		let bodies = printedBodies(of: session)
		#expect(bodies.contains(String(localized: .IRC.declinedSecureFileTransferOffer("alice", "file.txt"))) == false)
		#expect(bodies.contains(String(localized: .IRC.declinedSecureDirectChatOffer("alice"))) == false)
	}

	@Test("Declines share the offer throttle, so a flood prints a bounded number of lines")
	func declinesAreThrottled() throws {
		let session = makeSession()
		let budget = DCCOfferThrottle.perSenderLimit

		for index in 0 ..< budget + 3 {
			let text = switch index % 3 {
			case 0: "SSEND file.txt 1568397154 5000 42"
			case 1: "SCHAT chat 1568397154 5000"
			default: "TSEND file.txt 1568397154 5000 42"
			}
			try offer(text, on: session)
		}

		#expect(session.printedLines.count == budget)
	}

	@Test("An offer that is not addressed to this user is not declined")
	func offerToSomeoneElse() throws {
		let session = makeSession()
		let message = try #require(Message(
			line: ":alice!a@example.test PRIVMSG #channel :\u{01}DCC SSEND file.txt 1568397154 5000 42\u{01}",
			on: session
		))

		session.processIncomingMessage(message)

		#expect(printedBodies(of: session).contains(
			String(localized: .IRC.declinedSecureFileTransferOffer("alice", "file.txt"))
		) == false)
	}
}
