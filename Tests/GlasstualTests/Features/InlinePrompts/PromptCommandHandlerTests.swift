// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing

/** Typed commands against the questions waiting in one conversation. */
@MainActor
@Suite("Prompt command handler", .timeLimit(.minutes(1)))
struct PromptCommandHandlerTests {
	private static func request(_ title: String, field: PromptField? = nil) -> AlertRequest {
		AlertRequest(
			title: title, body: "", defaultButton: "Send", alternateButton: "Cancel", field: field,
			keywords: [.default: .send, .alternate: .cancel]
		)
	}

	private func perform(_ line: String, registry: PendingPromptRegistry, in itemID: String = "c1") throws -> PromptCommandOutcome {
		let handler = PromptCommandHandler(registry: registry, itemID: itemID, sessionID: "s1") { $0 == "c1" ? "#chan" : nil }
		return try handler.perform(#require(PromptCommand(line: line)))
	}

	private func register(_ request: AlertRequest, on registry: PendingPromptRegistry, in itemID: String = "c1") -> (PendingPrompt, Task<
		PromptAnswer,
		Never
	>) {
		let prompt = registry.register(request, scope: PromptScope(sessionID: "s1"), route: .inline(itemID: itemID)).prompt
		let task = Task { await registry.wait(for: prompt, waiter: UUID()) }
		return (prompt, task)
	}

	@Test("/yes answers the one question waiting here")
	func yesAnswersTheOnlyQuestion() async throws {
		let registry = PendingPromptRegistry()
		let (_, answer) = register(Self.request("Send?"), on: registry)
		await Task.yield()

		#expect(try perform("/yes", registry: registry) == .answered)
		#expect(await answer.value.response == .default)
	}

	@Test("With several waiting, /no names none and lists them")
	func severalWaiting() throws {
		let registry = PendingPromptRegistry()
		let (first, _) = register(Self.request("Send?"), on: registry)
		let (second, _) = register(Self.request("Delete?"), on: registry)

		let outcome = try perform("/no", registry: registry)

		guard case let .feedback(text) = outcome else {
			Issue.record("Expected a list, got \(outcome)")
			return
		}
		#expect(text.contains(String(localized: .InlinePrompts.listEntry(first.number, "Send?"))))
		#expect(text.contains(String(localized: .InlinePrompts.listEntry(second.number, "Delete?"))))
		#expect(registry.pending.count == 2)
		registry.withdraw { _ in true }
	}

	@Test("A question waiting in another conversation is not answered by a bare /yes")
	func otherConversation() throws {
		let registry = PendingPromptRegistry()
		_ = register(Self.request("Send?"), on: registry, in: "c2")

		#expect(try perform("/yes", registry: registry) == .feedback(String(localized: .InlinePrompts.noneWaitingHere)))
		#expect(registry.pending.count == 1)
		registry.withdraw { _ in true }
	}

	@Test("An unknown number is reported")
	func unknownNumber() throws {
		#expect(try perform("/answer 99 send", registry: PendingPromptRegistry()) == .feedback(
			String(localized: .InlinePrompts.unknownNumber(99))
		))
	}

	@Test("A secret typed after /answer is refused, kept out of history, and its field focused")
	func secretRefused() throws {
		let registry = PendingPromptRegistry()
		let (prompt, _) = register(Self.request("Password", field: .secure(placeholder: "Password")), on: registry)

		let outcome = try perform("/answer \(prompt.number) hunter2", registry: registry)

		#expect(outcome == .refusedSecret(String(localized: .InlinePrompts.secretAsArgument(prompt.number))))
		#expect(outcome.keepsLineInHistory == false)
		#expect(registry.fieldFocusRequest == prompt.number)
		#expect(prompt.text.isEmpty)
		registry.withdraw { _ in true }
	}

	@Test("/answer with a number alone focuses a field question")
	func focusField() throws {
		let registry = PendingPromptRegistry()
		let (prompt, _) = register(Self.request("Virtual host", field: .text(placeholder: "", initialValue: "")), on: registry)

		#expect(try perform("/answer \(prompt.number)", registry: registry) == .focusedField)
		#expect(registry.fieldFocusRequest == prompt.number)
		registry.withdraw { _ in true }
	}

	@Test("/prompts lists every waiting question and where it waits")
	func listing() throws {
		let registry = PendingPromptRegistry()
		let (here, _) = register(Self.request("Send?"), on: registry)
		let dialog = registry.register(Self.request("Open?"), scope: .application, route: .dialog(revealsMainWindow: true)).prompt

		let outcome = try perform("/prompts", registry: registry)

		#expect(outcome == .feedback([
			String(localized: .InlinePrompts.listEntryWithLocation(here.number, "Send?", "#chan")),
			String(localized: .InlinePrompts.listEntryWithLocation(
				dialog.number, "Open?", String(localized: .InlinePrompts.locationDialog)
			)),
		].joined(separator: "\n")))
		registry.withdraw { _ in true }
	}
}
