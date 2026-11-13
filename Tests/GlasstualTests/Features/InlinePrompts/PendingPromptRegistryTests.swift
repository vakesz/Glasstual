// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing

/** Every waiting question, numbered and settled exactly once. */
@MainActor
@Suite("Pending prompt registry", .timeLimit(.minutes(1)))
struct PendingPromptRegistryTests {
	private static let question = AlertRequest(
		title: "Delete #old?", body: "It cannot be undone.",
		defaultButton: "Delete", alternateButton: "Cancel", destructiveButton: .default,
		keywords: [.default: .delete, .alternate: .cancel]
	)

	private static let scope = PromptScope(sessionID: "s1", conversationID: "c1")

	private func waiting(
		on registry: PendingPromptRegistry, _ prompt: PendingPrompt
	) async throws -> Task<PromptAnswer, Never> {
		let task = Task { await registry.wait(for: prompt, waiter: UUID()) }
		await Task.yield()
		return task
	}

	@Test("Numbers count up and are never reused")
	func numbering() {
		let registry = PendingPromptRegistry()
		let first = registry.register(Self.question, scope: Self.scope, route: .inline(itemID: "c1")).prompt
		var other = Self.question
		other.title = "Delete #older?"
		let second = registry.register(other, scope: Self.scope, route: .inline(itemID: "c1")).prompt
		registry.withdraw(first)
		other.title = "Delete #oldest?"
		let third = registry.register(other, scope: Self.scope, route: .inline(itemID: "c1")).prompt

		#expect([first.number, second.number, third.number] == [Int](1 ... 3))
		#expect(registry.pending.map(\.number) == [2, 3])
		#expect(registry.prompt(numbered: 1) === nil)
	}

	@Test("The same question asked twice is one question, answered for both")
	func coalescing() async throws {
		let registry = PendingPromptRegistry()
		let (first, isNew) = registry.register(Self.question, scope: Self.scope, route: .inline(itemID: "c1"))
		let (second, secondIsNew) = registry.register(Self.question, scope: Self.scope, route: .inline(itemID: "c1"))
		let one = try await waiting(on: registry, first)
		let two = try await waiting(on: registry, second)

		#expect(isNew)
		#expect(secondIsNew == false)
		#expect(first === second)
		#expect(registry.answer(first, with: .default) == .answered)
		#expect(await one.value.response == .default)
		#expect(await two.value.response == .default)
	}

	@Test("An answer is taken once; a second one finds nothing")
	func answeredOnce() async throws {
		let registry = PendingPromptRegistry()
		let prompt = registry.register(Self.question, scope: Self.scope, route: .inline(itemID: "c1")).prompt
		let waiter = try await waiting(on: registry, prompt)

		#expect(registry.answer(prompt, with: .alternate) == .answered)
		#expect(registry.answer(prompt, with: .default) == .notPending)
		#expect(await waiter.value.response == .alternate)
		#expect(registry.pending.isEmpty)
	}

	@Test("A button the question does not have is refused")
	func unknownButtonIsRefused() {
		let registry = PendingPromptRegistry()
		let prompt = registry.register(Self.question, scope: Self.scope, route: .inline(itemID: "c1")).prompt

		#expect(registry.answer(prompt, with: .other) == .notPending)
		#expect(registry.pending.count == 1)
	}

	@Test("Withdrawing answers with the Escape button")
	func withdrawAnswersEscape() async throws {
		let registry = PendingPromptRegistry()
		let prompt = registry.register(Self.question, scope: Self.scope, route: .inline(itemID: "c1")).prompt
		let waiter = try await waiting(on: registry, prompt)

		registry.withdraw { $0.scope.sessionID == "s1" }

		#expect(await waiter.value == .escape(for: Self.question))
		#expect(registry.pending.isEmpty)
	}

	@Test("The last asker to stop waiting withdraws the question")
	func lastWaiterWithdraws() async {
		let registry = PendingPromptRegistry()
		let prompt = registry.register(Self.question, scope: Self.scope, route: .inline(itemID: "c1")).prompt
		let id = UUID()
		let task = Task { await registry.wait(for: prompt, waiter: id) }
		await Task.yield()

		registry.removeWaiter(id, from: prompt)

		#expect(await task.value.response == Self.question.escapeButton)
		#expect(registry.pending.isEmpty)
	}

	@Test("An answer after the connection changed withdraws the question instead")
	func connectionChange() async throws {
		let registry = PendingPromptRegistry()
		var scope = Self.scope
		scope.connection = PromptConnection(startupIdentifier: UUID(), socketIdentifier: "a")
		registry.isConnectionCurrent = { _ in false }
		let prompt = registry.register(Self.question, scope: scope, route: .inline(itemID: "c1")).prompt
		let waiter = try await waiting(on: registry, prompt)

		#expect(registry.answer(prompt, with: .default) == .connectionChanged)
		#expect(await waiter.value.response == Self.question.escapeButton)
	}

	@Test("Don't ask again counts only where the question offers it")
	func rememberNeedsASuppressionKey() async throws {
		let registry = PendingPromptRegistry()
		var offering = Self.question
		offering.suppressionKey = "Key"
		let withKey = registry.register(offering, scope: Self.scope, route: .inline(itemID: "c1")).prompt
		var other = Self.question
		other.title = "Other"
		let withoutKey = registry.register(other, scope: Self.scope, route: .inline(itemID: "c1")).prompt
		let first = try await waiting(on: registry, withKey)
		let second = try await waiting(on: registry, withoutKey)

		registry.answer(withKey, with: .default, remember: true)
		registry.answer(withoutKey, with: .default, remember: true)

		#expect(await first.value.outcome.isSuppressed)
		#expect(await second.value.outcome.isSuppressed == false)
	}

	@Test("What was typed into a field goes to the asker and is not kept")
	func fieldTextIsHandedOverAndDropped() async throws {
		let registry = PendingPromptRegistry()
		var secret = Self.question
		secret.field = .secure(placeholder: "Password")
		let prompt = registry.register(secret, scope: Self.scope, route: .inline(itemID: "c1")).prompt
		let waiter = try await waiting(on: registry, prompt)
		prompt.text = "hunter2"

		registry.answer(prompt, with: .default, text: prompt.text)

		#expect(await waiter.value.text == "hunter2")
		#expect(prompt.text.isEmpty)
	}

	@Test("A question is found by its asker's own reference, in its own session only")
	func referenceLookup() {
		let registry = PendingPromptRegistry()
		var dcc = Self.question
		dcc.reference = "d1"
		let prompt = registry.register(dcc, scope: Self.scope, route: .inline(itemID: "c1")).prompt

		#expect(registry.prompt(reference: "D1", inSession: "s1") === prompt)
		#expect(registry.prompt(reference: "d1", inSession: "s2") === nil)
	}
}
