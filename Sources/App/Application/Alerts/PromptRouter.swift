// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/** The one place a question is asked, whichever form it takes.

 Every question is recorded in the registry under a number, so a typed command
 can answer it in either form. Then it is shown: as an alert through the
 system alert presenter, or as a card in a conversation, which the
 conversation draws from the registry. A question the reader asked not to see
 again is answered from the recorded choice without being shown at all, in
 either form. */
@MainActor
final class PromptRouter: PromptPresenting {
	let registry: PendingPromptRegistry
	private let dialogs: any AlertPresenter

	/// The reader's choice, read when each question is asked.
	var style: @MainActor () -> InteractionStyle = { SettingsKeys.Interaction.style.value }
	/// The chat item a question about `scope` appears in, or `nil` when there
	/// is no conversation to show it in.
	var resolveAnchor: @MainActor (PromptScope) -> String? = { _ in nil }
	/// Brings the main window forward for a question the reader just raised.
	var revealWindow: @MainActor () -> Void = {}
	/// Tells assistive technology a question appeared in the conversation.
	var announce: @MainActor (PendingPrompt) -> Void = { _ in }

	init(registry: PendingPromptRegistry, dialogs: any AlertPresenter = SystemAlertPresenter()) {
		self.registry = registry
		self.dialogs = dialogs
	}

	func ask(_ request: AlertRequest, about scope: PromptScope) async -> PromptAnswer {
		guard Task.isCancelled == false else { return .escape(for: request) }
		let prepared: AlertRequest
		let suppressionKey: String?
		switch Alerts.prepare(request) {
		case let .suppressed(response):
			return PromptAnswer(outcome: AlertOutcome(response: response, isSuppressed: true))
		case let .show(request, key):
			prepared = request
			suppressionKey = key
		}

		let route = PromptRouting.route(
			style: style(),
			allowsInline: prepared.allowsInline,
			origin: scope.origin,
			anchor: resolveAnchor(scope),
			revealsMainWindow: scope.revealsMainWindow
		)
		let (prompt, isNew) = registry.register(prepared, scope: scope, route: route)
		if isNew {
			show(prompt)
		}

		let waiter = UUID()
		let registry = registry
		let answer = await withTaskCancellationHandler {
			await registry.wait(for: prompt, waiter: waiter)
		} onCancel: {
			Task { @MainActor in registry.removeWaiter(waiter, from: prompt) }
		}
		return Alerts.finish(answer, suppressionKey: suppressionKey)
	}

	func withdrawPrompts(inSession sessionID: String, connectionBoundOnly: Bool) {
		registry.withdraw { prompt in
			prompt.scope.sessionID == sessionID && (connectionBoundOnly == false || prompt.scope.connection != nil)
		}
	}

	func withdrawPrompts(inConversation conversationID: String) {
		registry.withdraw { $0.scope.conversationID == conversationID }
	}

	private func show(_ prompt: PendingPrompt) {
		switch prompt.route {
		case let .dialog(revealsMainWindow):
			let presentation: AlertPresentation = revealsMainWindow ? .mainWindow : .anyVisibleWindow
			let dialogs = dialogs
			let registry = registry
			prompt.dialog = Task { [weak prompt] in
				guard let prompt else { return }
				let result = await dialogs.present(prompt.request, in: presentation)
				registry.answer(prompt, with: result.response, text: result.text, remember: result.suppressionChecked)
			}
		case .inline:
			if prompt.scope.revealsMainWindow {
				revealWindow()
			}
			announce(prompt)
		}
	}
}
