// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing

/** The commands a card offers. A security question shows its answer spelled
 out, because `/yes` does not answer it. */
@Suite("Prompt hints")
struct PromptHintTests {
	@Test("A routine yes-or-no question offers /yes and /no")
	func routine() {
		let request = AlertRequest(
			title: "Send?", body: "", defaultButton: "Send", alternateButton: "Cancel",
			keywords: [.default: .send, .alternate: .cancel]
		)
		#expect(PromptHint.commands(for: request, number: 4) == ["/yes", "/no"])
	}

	@Test("A security question offers the spelled-out answer, never /yes")
	func security() {
		let request = ServerSession.credentialConsentAlert(host: "irc.example.test")
		#expect(request.affirmativeButton == nil)
		#expect(PromptHint.commands(for: request, number: 3) == ["/answer 3 send", "/no"])
	}

	@Test("A question with two ways forward names both")
	func threeButtons() {
		let request = AlertRequest(
			title: "Send 3 lines as one message?", body: "", defaultButton: "Send as One",
			alternateButton: "Send Line by Line", otherButton: "Cancel", cancelButton: .other,
			keywords: [.default: .oneMessage, .alternate: .lineByLine, .other: .cancel]
		)
		#expect(PromptHint.commands(for: request, number: 7) == [
			"/answer 7 one-message", "/answer 7 line-by-line", "/no",
		])
	}

	@Test("A notice is dismissed with /yes, a field question is answered in its field")
	func noticeAndField() {
		let notice = AlertRequest(title: "No logs", body: "", defaultButton: "OK")
		var field = AlertRequest(title: "Virtual host", body: "", defaultButton: "OK", alternateButton: "Cancel")
		field.field = .text(placeholder: "vhost", initialValue: "")

		#expect(PromptHint.commands(for: notice, number: 1) == ["/yes"])
		#expect(PromptHint.commands(for: field, number: 2) == ["/answer 2", "/no"])
	}

	@Test("A DCC question shows its own /dcc command")
	func dcc() {
		let trust = AlertRequest(
			title: "Verify", body: "", defaultButton: "Trust and Remember", alternateButton: "Cancel",
			otherButton: "Trust Once", sensitivity: .security,
			keywords: [.default: .remember, .alternate: .reject, .other: .once], reference: "d1"
		)
		let offer = AlertRequest(
			title: "Chat?", body: "", defaultButton: "Accept", alternateButton: "Decline",
			sensitivity: .security, keywords: [.default: .accept, .alternate: .decline], reference: "d2"
		)
		#expect(PromptHint.commands(for: trust, number: 5) == ["/dcc trust d1 remember|once|reject"])
		#expect(PromptHint.commands(for: offer, number: 6) == ["/dcc accept d2", "/dcc decline d2"])
	}

	@Test("Return in a security question's alert presses only its way out")
	func securityReturnKey() {
		let consent = ServerSession.credentialConsentAlert(host: "irc.example.test")
		let offer = AlertRequest(
			title: "Chat?", body: "", defaultButton: "Accept", alternateButton: "Decline",
			sensitivity: .security
		)
		#expect(consent.returnButton == .default)
		#expect(consent.escapeButton == .default)
		#expect(offer.returnButton == .alternate)
	}
}
