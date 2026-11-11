// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing

/// What a session does with a DCC CHAT offer before any prompt is made.
@MainActor
@Suite("Direct chat offer routing")
struct ServerSessionDirectChatRoutingTests {
	/// A routable address (93.123.215.98), so only the throttle and the
	/// pending-request check decide the outcome.
	private static let activeOffer = "CHAT chat 1568397154 5000"

	@Test("An offer that does not parse is reported and creates no conversation", arguments: [
		"CHAT chat invalid 5000",
		"CHAT chat 3232235777 0",
		"garbage",
	])
	func unparseableOfferPrintsInvalidRequest(text: String) throws {
		let session = TestServerSession()
		let conversationsBefore = session.conversationList.count

		session.receivedDCCChatQuery("alice", text: text)

		#expect(session.printedLines.count == 1)
		let line = try #require(session.printedLines.firstObject as? [String: Any])
		#expect(line["messageBody"] as? String == String(localized: .IRC.glasstualHasReceivedADccRequest("alice")))
		#expect((line["lineType"] as? NSNumber)?.uintValue == ChatLineKind.dccFileTransfer.rawValue)
		#expect(session.recordedOutput.presentedAlerts.isEmpty)
		#expect(session.directChatConversation(forNickname: "alice") == nil)
		#expect(session.conversationList.count == conversationsBefore)
	}

	@Test("A reply naming a port and token with no listening request is ignored and costs no budget")
	func replyWithoutPendingRequestIsIgnored() {
		let session = TestServerSession()

		for _ in 0 ..< DCCOfferThrottle.perSenderLimit + 2 {
			session.receivedDCCChatQuery("alice", text: "CHAT chat 1568397154 5000 T9")
		}

		#expect(session.printedLines.count == 0)
		#expect(session.recordedOutput.presentedAlerts.isEmpty)
		#expect(session.directChatConversation(forNickname: "alice") == nil)

		// Ignored replies never reached the throttle, so the full budget is left.
		for _ in 0 ..< DCCOfferThrottle.perSenderLimit {
			session.receivedDCCChatQuery("alice", text: Self.activeOffer)
		}

		#expect(session.recordedOutput.presentedAlerts.count == DCCOfferThrottle.perSenderLimit)
	}

	@Test("One sender gets its budget of unsolicited offers and no more, whatever the nickname's case")
	func perSenderThrottle() {
		let session = TestServerSession()
		let budget = DCCOfferThrottle.perSenderLimit

		for index in 0 ..< budget {
			session.receivedDCCChatQuery(index.isMultiple(of: 2) ? "alice" : "ALICE", text: Self.activeOffer)
		}

		#expect(session.recordedOutput.presentedAlerts.count == budget)
		let printedBefore = session.printedLines.count

		session.receivedDCCChatQuery("alice", text: Self.activeOffer)
		session.receivedDCCChatQuery("Alice", text: Self.activeOffer)

		#expect(session.recordedOutput.presentedAlerts.count == budget)
		#expect(session.printedLines.count == printedBefore)
	}

	@Test("Everyone together gets the overall budget of unsolicited offers")
	func overallThrottle() {
		let session = TestServerSession()
		let overall = DCCOfferThrottle.overallLimit
		let perSender = DCCOfferThrottle.perSenderLimit
		var admitted = 0
		var sender = 0

		while admitted < overall {
			let count = min(perSender, overall - admitted)
			for _ in 0 ..< count {
				session.receivedDCCChatQuery("peer\(sender)", text: Self.activeOffer)
			}
			admitted += count
			sender += 1
		}

		#expect(session.recordedOutput.presentedAlerts.count == overall)

		session.receivedDCCChatQuery("newcomer", text: Self.activeOffer)

		#expect(session.recordedOutput.presentedAlerts.count == overall)
	}

	/// A passive offer: accepting it would listen and answer whoever holds the
	/// sender's nickname, which is what a stale answer must not do.
	private static let passiveOffer = "CHAT chat 0 0 T12"

	@Test("Accepting an offer after the connection that carried it was replaced does nothing")
	func staleAcceptanceIsIgnored() throws {
		let session = TestServerSession()
		session.markAsLoggedIn()
		session.receivedDCCChatQuery("alice", text: Self.passiveOffer)
		let completion = try #require(session.recordedOutput.presentedAlertCompletions.first)

		// A reconnect starts a new startup, and the session is logged in again.
		session.startup = StartupState()
		completion(AlertOutcome(response: .default, isSuppressed: false))

		#expect(session.directChatConversation(forNickname: "alice") == nil)
	}

	@Test("Declining an offer still says so after a reconnect")
	func staleDeclinePrintsTheDeclinedLine() throws {
		let session = TestServerSession()
		session.markAsLoggedIn()
		session.receivedDCCChatQuery("alice", text: Self.passiveOffer)
		let completion = try #require(session.recordedOutput.presentedAlertCompletions.first)
		session.startup = StartupState()
		let printedBefore = session.printedLines.count

		completion(AlertOutcome(response: .alternate, isSuppressed: false))

		#expect(session.printedLines.count == printedBefore + 1)
		let line = try #require(session.printedLines.lastObject as? [String: Any])
		#expect(line["messageBody"] as? String == String(localized: .IRC.declinedDirectChatRequest("alice")))
		#expect(session.directChatConversation(forNickname: "alice") == nil)
	}
}
