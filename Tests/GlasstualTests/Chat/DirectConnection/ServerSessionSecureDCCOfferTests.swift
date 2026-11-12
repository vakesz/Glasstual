// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing

/// Secure offers go through every check a plain one does, are listed or put to
/// the user like one, and are declined in so many words when the user turned
/// them off. Forms Glasstual does not take part in are declined by name.
@MainActor
@Suite("Secure DCC offer routing")
struct ServerSessionSecureDCCOfferTests {
	private func makeSession(acceptsSecureOffers: Bool = true) -> TestServerSession {
		var settings = ChatSettings.current()
		settings.fileTransferRequestReplyAction = .openDialog
		settings.fileTransferAcceptsSecureOffers = acceptsSecureOffers
		let session = TestServerSession(
			configDictionary: ["nickname": "me"],
			nicknamePassword: nil,
			fixture: ChatEnvironmentFixture(settings: settings)
		)
		session.userNickname = "me"
		session.identity.hostmask = "me!u@h"
		session.markAsLoggedIn()
		session.recordedOutput.answersManually = true
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

	@Test("A secure file offer is listed as encrypted, in every form", arguments: [
		"SSEND file.txt 1568397154 5000 42",
		"SSEND file.txt 1568397154 0 42 T7",
		"ssend file.txt 1568397154 0 42 7",
	])
	func secureFileOfferIsListed(text: String) throws {
		let session = makeSession()

		try offer(text, on: session)

		#expect(printedBodies(of: session) == [
			String(localized: .IRC.receivedSecureFileTransferRequest("alice", "file.txt", LocalizedByteCount.formatted(42))),
		])
	}

	@Test("A secure file offer for a private address is refused like a plain one")
	func secureOfferForPrivateAddress() throws {
		let session = makeSession()

		try offer("SSEND file.txt 3232235777 5000 42", on: session)

		#expect(printedBodies(of: session) == [String(localized: .IRC.glasstualHasReceivedADccRequest("alice"))])
	}

	@Test("With secure offers turned off, a secure file offer is declined by name")
	func secureFileOfferDeclinedBySetting() throws {
		let session = makeSession(acceptsSecureOffers: false)

		try offer("SSEND file.txt 1568397154 5000 42", on: session)

		#expect(printedBodies(of: session) == [String(localized: .IRC.secureFileOfferDeclinedBySetting("alice", "file.txt"))])
	}

	@Test("An SSEND naming a token is never taken as the answer to a plain reverse offer")
	func secureReplyNeedsSecureOffer() throws {
		let session = makeSession()

		try offer("SSEND file.txt 1568397154 5000 42 7", on: session)

		#expect(printedBodies(of: session) == [String(localized: .IRC.glasstualHasReceivedADccRequest("alice"))])
	}

	@Test("A secure chat offer is put to the user as encrypted, with a typed way to answer it")
	func secureChatOfferIsAsked() async throws {
		let session = makeSession()

		try offer("SCHAT chat 1568397154 5000", on: session)
		try await Eventually.until("the question") { session.recordedOutput.presentedAlerts.isEmpty == false }

		let alert = try #require(session.recordedOutput.presentedAlerts.first)
		#expect(alert.reference == "d1")
		#expect(alert.sensitivity == .security)
		#expect(alert.keyword(for: .default) == .accept)
		#expect(alert.keyword(for: .alternate) == .decline)
		#expect(alert.title == PromptStrings.DirectChat.secureTitle(sender: "alice"))
		#expect(alert.body == ConnectionSafetyStrings.DirectChat.secureRequestBody(sender: "alice", address: "93.123.215.98"))
		#expect(printedBodies(of: session) == [
			String(localized: .IRC.wantsToStartASecureDirectChat("alice")),
		])
	}

	@Test("A chat offer is answered once, by the alert or by /dcc decline, whichever comes first")
	func chatOfferIsAnsweredOnce() async throws {
		let session = makeSession()
		try offer("SCHAT chat 0 0 T9", on: session)
		try await Eventually.until("the question") { session.recordedOutput.presentedAlertCompletions.isEmpty == false }
		let completion = try #require(session.recordedOutput.presentedAlertCompletions.first)

		session.handleDCCCommand(CommandArguments("decline d1"), command: "DCC", targetConversation: nil)
		completion(AlertOutcome(response: .default, isSuppressed: false))
		session.handleDCCCommand(CommandArguments("accept d1"), command: "DCC", targetConversation: nil)

		let bodies = printedBodies(of: session)
		#expect(bodies.filter { $0 == String(localized: .IRC.declinedDirectChatRequest("alice")) }.count == 1)
		#expect(bodies.last == String(localized: .IRC.dccQuestionUnknown("d1")))
		#expect(session.directChatConversation(forNickname: "alice") == nil)
	}

	@Test("An accepted chat offer opens nothing once the connection it came over is gone")
	func chatOfferAnsweredAfterReconnect() throws {
		let session = makeSession()
		try offer("CHAT chat 0 0 T9", on: session)

		session.startup = StartupState()
		#expect(session.answerDCCChatOffer("d1", accept: true) == .answered)

		#expect(session.directChatConversation(forNickname: "alice") == nil)
	}

	@Test("With secure offers turned off, a secure chat offer is declined by name")
	func secureChatOfferDeclinedBySetting() throws {
		let session = makeSession(acceptsSecureOffers: false)

		try offer("SCHAT chat 1568397154 5000", on: session)

		#expect(printedBodies(of: session) == [String(localized: .IRC.secureChatOfferDeclinedBySetting("alice"))])
		#expect(session.recordedOutput.presentedAlerts.isEmpty)
	}

	@Test("A passive chat reply only answers a listening chat of the same kind", arguments: [
		(true, true, true), (false, false, true), (true, false, false), (false, true, false),
	])
	func passiveReplyMatchesKind(replyIsSecure: Bool, listeningIsSecure: Bool, matches: Bool) {
		let reply = DirectChatOffer(address: "203.0.113.5", port: 5000, token: "9", isSecure: replyIsSecure)

		#expect(DirectChatPolicy.reply(reply, answersListeningChatThatIsSecure: listeningIsSecure) == matches)
	}

	@Test("A passive secure chat reply with no listening chat opens nothing")
	func unmatchedSecureReply() throws {
		let session = makeSession()

		try offer("SCHAT chat 1568397154 5000 T9", on: session)

		#expect(session.printedLines.count == 0)
		#expect(session.recordedOutput.presentedAlerts.isEmpty)
	}

	@Test("A turbo or reversed offer is declined by name", arguments: ["TSEND", "TSSEND", "STSEND", "SRECV"])
	func unsupportedOfferIsDeclined(verb: String) throws {
		let session = makeSession()

		try offer("\(verb) file.txt 1568397154 5000 42", on: session)

		#expect(printedBodies(of: session) == [String(localized: .IRC.declinedUnsupportedDccOffer("alice", verb))])
		#expect(session.recordedOutput.presentedAlerts.isEmpty)
	}

	@Test("A replayed secure offer is history: nothing is listed or asked")
	func replayedOfferIsIgnored() throws {
		let session = makeSession()

		try offer("SSEND file.txt 1568397154 5000 42", on: session, replayed: true)
		try offer("SCHAT chat 1568397154 5000", on: session, replayed: true)

		let bodies = printedBodies(of: session)
		#expect(bodies.contains(
			String(localized: .IRC.receivedSecureFileTransferRequest("alice", "file.txt", LocalizedByteCount.formatted(42)))
		) == false)
		#expect(bodies.contains(String(localized: .IRC.wantsToStartASecureDirectChat("alice"))) == false)
		#expect(session.recordedOutput.presentedAlerts.isEmpty)
		#expect(session.dccDecisions.isEmpty)
	}

	@Test("Secure offers share the offer throttle, so a flood is bounded")
	func secureOffersAreThrottled() throws {
		let session = makeSession()
		let budget = DCCOfferThrottle.perSenderLimit

		for index in 0 ..< budget + 3 {
			let text = switch index % 3 {
			case 0: "SSEND file.txt 1568397154 5000 42"
			case 1: "TSEND file.txt 1568397154 5000 42"
			default: "SSEND other.txt 1568397154 5000 42"
			}
			try offer(text, on: session)
		}

		#expect(session.printedLines.count == budget)
	}

	@Test("An offer that is not addressed to this user is not acted on")
	func offerToSomeoneElse() throws {
		let session = makeSession()
		let message = try #require(Message(
			line: ":alice!a@example.test PRIVMSG #channel :\u{01}DCC SSEND file.txt 1568397154 5000 42\u{01}",
			on: session
		))

		session.processIncomingMessage(message)

		#expect(printedBodies(of: session).contains(
			String(localized: .IRC.receivedSecureFileTransferRequest("alice", "file.txt", LocalizedByteCount.formatted(42)))
		) == false)
	}
}
