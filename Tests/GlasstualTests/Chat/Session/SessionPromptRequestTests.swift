// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing

/** The questions a session asks, as they leave the session: each names its
 answers by word, says how hard it is to answer by accident, and appears where
 it belongs when the reader chose the conversation. */
@MainActor
@Suite("Session prompt requests", .timeLimit(.minutes(1)))
struct SessionPromptRequestTests {
	private func router(for session: TestServerSession) -> PromptRouter {
		let router = PromptRouter(registry: PendingPromptRegistry())
		router.style = { .conversation }
		router.resolveAnchor = { $0.conversationID ?? $0.sessionID }
		session.environment.services.prompts = router
		return router
	}

	@Test("Sending a password to an unchecked certificate is a security question answered by send")
	func credentialConsent() {
		for changed in [false, true] {
			let request = ServerSession.credentialConsentAlert(host: "irc.example.test", certificateChanged: changed)
			#expect(request.sensitivity == .security)
			#expect(request.keyword(for: .alternate) == .send)
			#expect(request.keyword(for: .default) == .dontSend)
			#expect(request.escapeButton == .default)
			#expect(request.returnButton == .default)
			#expect(request.affirmativeButton == nil)
		}
	}

	@Test("A large message asks Send or Cancel and offers Don't ask again")
	func floodWarning() {
		let request = ServerSession.potentialFloodAlert
		#expect(request.sensitivity == .routine)
		#expect(request.suppressionKey != nil)
		#expect(request.keyword(for: .default) == .send)
		#expect(request.affirmativeButton == .default)
	}

	@Test("Multi-line sending names its three answers")
	func multiline() {
		let request = ServerSession.multilineChoiceAlert(for: MultilineProposal(
			lines: [], limits: MultilineLimits(maximumBytes: 4096, maximumLines: 10)
		))
		#expect(request.responses.map(request.keyword(for:)) == [.oneMessage, .lineByLine, .cancel])
		#expect(request.escapeButton == .other)
	}

	@Test("In the conversation style, a question about a conversation appears in it")
	func conversationQuestionGoesInline() async throws {
		let session = TestServerSession()
		let router = router(for: session)
		let channel = try #require(session.findConversationOrCreate("#inline"))
		var acted = false
		session.requestConfirmation(
			AlertRequest(title: "Q", body: "", defaultButton: "Delete", alternateButton: "Cancel",
			             keywords: [.default: .delete, .alternate: .cancel]),
			in: channel,
			perform: { _ in acted = true }
		)
		try await Eventually.until("the card") { router.registry.pending.count == 1 }
		let prompt = try #require(router.registry.pending.first)

		#expect(prompt.route == .inline(itemID: channel.uniqueIdentifier))
		router.registry.answer(prompt, with: .default)
		try await Eventually.until("the answer") { acted }
	}

	@Test("Asking to send a password appears in the server console")
	func credentialConsentGoesToTheConsole() async throws {
		let session = TestServerSession()
		let router = router(for: session)
		session.requestResponse(ServerSession.credentialConsentAlert(host: "h")) { _, _ in }
		try await Eventually.until("the card") { router.registry.pending.count == 1 }

		#expect(router.registry.pending.first?.route == .inline(itemID: session.uniqueIdentifier))
		#expect(router.registry.pending.first?.request.sensitivity == .security)
		router.registry.withdraw { _ in true }
	}

	@Test("Removing a profile from inside the Profile pane stays an alert there")
	func profileRemovalStaysInThePane() async throws {
		let session = TestServerSession()
		let presenter = session.recordedOutput
		session.environment.services.prompts = presenter
		let model = ServerProfileModel(session: session)

		model.confirmRemoval()
		try await Eventually.until("the question") { presenter.presentedScopes.isEmpty == false }

		#expect(presenter.presentedScopes.first?.origin == .guiSurface)
	}
}
