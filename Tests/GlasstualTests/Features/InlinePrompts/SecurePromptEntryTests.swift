// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing

/** A secret typed into a question's secure field goes to whoever asked and
 nowhere else: not the transcript, not input history, not the registry once
 the question is settled, and not left behind in a conversation the reader
 switched away from. */
@MainActor
@Suite("Secure prompt entry", .timeLimit(.minutes(1)))
struct SecurePromptEntryTests {
	private static let request = AlertRequest(
		title: "Password for irc.example.test", body: "", defaultButton: "Sign In", alternateButton: "Cancel",
		field: .secure(placeholder: "Password"), keywords: [.default: .submit, .alternate: .cancel]
	)

	@Test("The secret reaches the asker and is not kept")
	func secretReachesTheAsker() async {
		let registry = PendingPromptRegistry()
		let prompt = registry.register(Self.request, scope: PromptScope(sessionID: "s1"), route: .inline(itemID: "s1")).prompt
		let asking = Task { await registry.wait(for: prompt, waiter: UUID()) }
		await Task.yield()
		prompt.text = "correct horse"

		registry.answer(prompt, with: .default, text: prompt.text)

		#expect(await asking.value.text == "correct horse")
		#expect(prompt.text.isEmpty)
		#expect(registry.pending.isEmpty)
	}

	@Test("Leaving the conversation or the window forgets a half-typed secret and keeps the question")
	func switchingAwayDiscardsTheSecret() {
		let registry = PendingPromptRegistry()
		let secure = registry.register(Self.request, scope: PromptScope(sessionID: "s1"), route: .inline(itemID: "s1")).prompt
		var plain = Self.request
		plain.title = "Virtual host"
		plain.field = .text(placeholder: "", initialValue: "")
		let text = registry.register(plain, scope: PromptScope(sessionID: "s1"), route: .inline(itemID: "s1")).prompt
		secure.text = "half typed"
		text.text = "vhost.example"

		registry.discardTypedSecrets()

		#expect(secure.text.isEmpty)
		#expect(text.text == "vhost.example")
		#expect(registry.pending.count == 2)
		registry.withdraw { _ in true }
	}

	@Test("Withdrawing a question hands back no secret")
	func withdrawnSecretIsNotHandedOver() async {
		let registry = PendingPromptRegistry()
		let prompt = registry.register(Self.request, scope: PromptScope(sessionID: "s1"), route: .inline(itemID: "s1")).prompt
		let asking = Task { await registry.wait(for: prompt, waiter: UUID()) }
		await Task.yield()
		prompt.text = "typed but never sent"

		registry.withdraw(prompt)

		let answer = await asking.value
		#expect(answer.text == nil)
		#expect(answer.response == .alternate)
		#expect(prompt.text.isEmpty)
	}

	@Test("A secret typed after /answer is refused and stays out of input history")
	func secretOnTheCommandLine() throws {
		let registry = PendingPromptRegistry()
		let prompt = registry.register(Self.request, scope: PromptScope(sessionID: "s1"), route: .inline(itemID: "s1")).prompt
		let handler = PromptCommandHandler(registry: registry, itemID: "s1", sessionID: "s1")

		let outcome = try handler.perform(#require(PromptCommand(line: "/answer \(prompt.number) correct horse")))

		#expect(outcome.keepsLineInHistory == false)
		#expect(prompt.text.isEmpty)
		#expect(registry.pending.count == 1)
		registry.withdraw { _ in true }
	}
}
