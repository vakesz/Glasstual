// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing

/// Shows each alert until a test or a cancellation ends it, and records it.
@MainActor
private final class HeldAlertPresenter: AlertPresenter {
	private(set) var requests: [AlertRequest] = []
	private(set) var cancellations = 0
	private var pending: [CheckedContinuation<AlertPresenterResult, Never>] = []
	/// Answers at once with this button when set.
	var immediateResponse: AlertResponse?

	func present(_ request: AlertRequest, in _: AlertPresentation) async -> AlertPresenterResult {
		requests.append(request)
		if let immediateResponse {
			return AlertPresenterResult(response: immediateResponse, suppressionChecked: false)
		}
		return await withTaskCancellationHandler {
			await withCheckedContinuation { pending.append($0) }
		} onCancel: {
			Task { @MainActor in self.cancelAll(request) }
		}
	}

	private func cancelAll(_ request: AlertRequest) {
		cancellations += 1
		let waiting = pending
		pending.removeAll()
		for continuation in waiting {
			continuation.resume(returning: AlertPresenterResult(response: request.escapeButton, suppressionChecked: false))
		}
	}
}

/** The one funnel every question goes through: it records the question,
 shows it in the form the reader chose, and settles it exactly once. */
@MainActor
@Suite("Prompt router", .serialized, .timeLimit(.minutes(1)))
struct PromptRouterTests {
	private static let request = AlertRequest(
		title: "Send this large message?", body: "It is 12 lines long.",
		defaultButton: "Send", alternateButton: "Cancel",
		keywords: [.default: .send, .alternate: .cancel]
	)

	private func router(style: InteractionStyle, presenter: HeldAlertPresenter) -> PromptRouter {
		let router = PromptRouter(registry: PendingPromptRegistry(), dialogs: presenter)
		router.style = { style }
		router.resolveAnchor = { scope in scope.conversationID ?? scope.sessionID ?? "selected" }
		return router
	}

	private func untilAsked(_ router: PromptRouter, count: Int = 1) async throws {
		try await Eventually.until("the question") { router.registry.pending.count == count }
	}

	@Test("With dialogs chosen, the question is an alert and its answer comes back")
	func dialogs() async {
		let presenter = HeldAlertPresenter()
		presenter.immediateResponse = .default
		let router = router(style: .dialogs, presenter: presenter)

		let answer = await router.ask(Self.request, about: PromptScope(sessionID: "s1"))

		#expect(answer.response == .default)
		#expect(presenter.requests.count == 1)
		#expect(router.registry.pending.isEmpty)
	}

	@Test("In the conversation, no alert is shown and the card's answer comes back")
	func inline() async throws {
		let presenter = HeldAlertPresenter()
		let router = router(style: .conversation, presenter: presenter)

		let asking = Task { await router.ask(Self.request, about: PromptScope(sessionID: "s1", conversationID: "c1")) }
		try await untilAsked(router)
		let prompt = try #require(router.registry.pending.first)

		#expect(prompt.route == .inline(itemID: "c1"))
		#expect(router.registry.answer(prompt, with: .default) == .answered)
		#expect(await asking.value.response == .default)
		#expect(presenter.requests.isEmpty)
	}

	@Test("A question raised inside a sheet stays an alert in the conversation style")
	func guiSurfaceStaysADialog() async {
		let presenter = HeldAlertPresenter()
		presenter.immediateResponse = .alternate
		let router = router(style: .conversation, presenter: presenter)

		let answer = await router.ask(Self.request, about: .guiSurface)

		#expect(answer.response == .alternate)
		#expect(presenter.requests.count == 1)
	}

	@Test("A typed answer takes the alert down")
	func typedAnswerDismissesTheAlert() async throws {
		let presenter = HeldAlertPresenter()
		let router = router(style: .dialogs, presenter: presenter)

		let asking = Task { await router.ask(Self.request, about: PromptScope(sessionID: "s1")) }
		try await Eventually.until("the alert") { presenter.requests.count == 1 }
		let prompt = try #require(router.registry.pending.first)
		router.registry.answer(prompt, with: .default)

		#expect(await asking.value.response == .default)
		try await Eventually.until("the alert to come down") { presenter.cancellations == 1 }
	}

	@Test("Cancelling the asker withdraws the question with its Escape answer")
	func cancellationWithdraws() async throws {
		let presenter = HeldAlertPresenter()
		let router = router(style: .conversation, presenter: presenter)

		let asking = Task { await router.ask(Self.request, about: PromptScope(sessionID: "s1")) }
		try await untilAsked(router)
		asking.cancel()

		#expect(await asking.value.response == Self.request.escapeButton)
		try await Eventually.until("the card to go") { router.registry.pending.isEmpty }
	}

	@Test("A connection that ended withdraws only the questions bound to it")
	func connectionTeardownWithdrawsBoundQuestions() async throws {
		let presenter = HeldAlertPresenter()
		let router = router(style: .conversation, presenter: presenter)
		var bound = PromptScope(sessionID: "s1")
		bound.connection = PromptConnection(startupIdentifier: UUID(), socketIdentifier: "socket")
		var other = Self.request
		other.title = "Delete server?"

		let wire = Task { await router.ask(Self.request, about: bound) }
		let menu = Task { await router.ask(other, about: PromptScope(sessionID: "s1")) }
		try await untilAsked(router, count: 2)

		router.withdrawPrompts(inSession: "s1", connectionBoundOnly: true)

		#expect(await wire.value.response == Self.request.escapeButton)
		#expect(router.registry.pending.map(\.request.title) == ["Delete server?"])
		router.withdrawPrompts(inSession: "s1", connectionBoundOnly: false)
		#expect(await menu.value.response == other.escapeButton)
	}

	@Test("Removing a conversation withdraws its questions")
	func conversationRemovalWithdraws() async throws {
		let router = router(style: .conversation, presenter: HeldAlertPresenter())
		let asking = Task { await router.ask(Self.request, about: PromptScope(sessionID: "s1", conversationID: "c1")) }
		try await untilAsked(router)

		router.withdrawPrompts(inConversation: "c1")

		#expect(await asking.value.response == Self.request.escapeButton)
	}

	@Test("A question the reader asked not to see again is answered without being shown, in either form",
	      arguments: [InteractionStyle.dialogs, .conversation])
	func suppressed(_ style: InteractionStyle) async {
		let presenter = HeldAlertPresenter()
		let router = router(style: style, presenter: presenter)
		var request = Self.request
		let base = "PromptRouterTests \(UUID().uuidString)"
		request.suppressionKey = base
		AlertSuppression.record(.alternate, fullKey: AlertSuppression.suppressionKey(withBase: base))

		let answer = await router.ask(request, about: PromptScope(sessionID: "s1"))

		#expect(answer.outcome == AlertOutcome(response: .alternate, isSuppressed: true))
		#expect(presenter.requests.isEmpty)
		#expect(router.registry.pending.isEmpty)
	}

	@Test("Don't ask again chosen on a card is recorded for both forms")
	func rememberedOnACard() async throws {
		let router = router(style: .conversation, presenter: HeldAlertPresenter())
		var request = Self.request
		let base = "PromptRouterTests \(UUID().uuidString)"
		request.suppressionKey = base

		let asking = Task { await router.ask(request, about: PromptScope(sessionID: "s1")) }
		try await untilAsked(router)
		let prompt = try #require(router.registry.pending.first)
		router.registry.answer(prompt, with: .default, remember: true)
		_ = await asking.value

		#expect(AlertSuppression.recordedResponse(fullKey: AlertSuppression.suppressionKey(withBase: base)) == .default)
	}
}
