// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
@testable import Glasstual
import Testing

/** The questions menus, links and the application ask: each names its answers
 by word, and the ones about where something goes are security questions. */
@MainActor
@Suite("Application prompt requests", .timeLimit(.minutes(1)))
struct ApplicationPromptRequestTests {
	@Test("Opening a link in another application is a security question answered by open")
	func openLink() throws {
		let request = try TranscriptCommands.openLinkRequest(for: #require(URL(string: "https://example.test/")))
		#expect(request.sensitivity == .security)
		#expect(request.keyword(for: .alternate) == .open)
		#expect(request.escapeButton == .default)
		#expect(request.returnButton == .default)
		#expect(PromptHint.commands(for: request, number: 2) == ["/answer 2 open", "/no"])
	}

	@Test("Deleting a message asks for an optional reason and never deletes on Return")
	func deleteMessage() {
		let request = TranscriptMessageDeletion.request
		#expect(request.field?.isRequired == false)
		#expect(request.isDestructive(.default))
		#expect(request.returnButton == nil)
		#expect(request.escapeButton == .alternate)
		#expect(request.keyword(for: .default) == .delete)
	}

	@Test("A failed keychain save offers Retry by word")
	func keychainRetry() {
		var request = KeychainAlerts.failureAlert(CocoaError(.fileWriteUnknown), canRetry: true)
		request.keywords = [.default: .retry, .alternate: .cancel]
		#expect(request.affirmativeButton == .default)
		#expect(KeychainAlerts.failureAlert(CocoaError(.fileWriteUnknown), canRetry: false).isNotice)
	}

	@Test("A newer link withdraws the question about the one before it")
	func newerLinkWithdrawsTheCard() async throws {
		let router = PromptRouter(registry: PendingPromptRegistry())
		router.style = { .conversation }
		router.resolveAnchor = { _ in "console" }
		var performed: [ApplicationLink.Action] = []

		let first = ApplicationLinkHandler.open("glasstual://support-channel", prompts: router) { action, _ in
			performed.append(action)
		}
		try await Eventually.until("the first card") { router.registry.pending.count == 1 }
		let firstNumber = try #require(router.registry.pending.first?.number)
		let second = ApplicationLinkHandler.open("glasstual://testing-channel", prompts: router) { action, _ in
			performed.append(action)
		}
		await first?.value
		try await Eventually.until("the second card") {
			router.registry.pending.count == 1 && router.registry.pending.first?.number != firstNumber
		}
		let card = try #require(router.registry.pending.first)

		#expect(card.route == .inline(itemID: "console"))
		#expect(card.request.sensitivity == .security)
		router.registry.answer(card, with: .alternate)
		await second?.value
		#expect(performed == [.testingChannel])
	}
}
