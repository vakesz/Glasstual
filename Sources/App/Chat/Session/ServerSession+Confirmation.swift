// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

extension ServerSession {
	/// The connection a question asked now is bound to, or `nil` while there
	/// is none.
	var promptConnection: PromptConnection? {
		guard socket != nil else { return nil }
		return PromptConnection(startupIdentifier: startup.identifier, socketIdentifier: socket?.uniqueIdentifier)
	}

	/** Where a question about this session belongs.

	 A question about a conversation appears in it; any other appears in the
	 server console. `boundToConnection` ties the question to the connection it
	 was asked on, so the question is withdrawn when that connection ends. */
	func promptScope(
		in conversation: Conversation? = nil,
		boundToConnection: Bool = true,
		origin: PromptOrigin = .conversation,
		revealsMainWindow: Bool = true
	) -> PromptScope {
		PromptScope(
			sessionID: uniqueIdentifier,
			conversationID: conversation?.uniqueIdentifier,
			connection: boundToConnection ? promptConnection : nil,
			origin: origin,
			revealsMainWindow: revealsMainWindow
		)
	}

	/// Keeps a pending user decision in this session. A delayed answer cannot
	/// act on a replacement connection, a removed conversation or a cancelled
	/// task.
	func requestConfirmation(
		_ request: AlertRequest,
		in conversation: Conversation? = nil,
		isCurrent: @escaping @MainActor (ServerSession) -> Bool = { _ in true },
		perform action: @escaping @MainActor (ServerSession) -> Void
	) {
		requestAnswer(request, in: conversation, isCurrent: isCurrent, unattended: .default) { session, answer in
			guard answer.response == .default else { return }
			action(session)
		}
	}

	/** Asks a question whose answer is the button, not a yes or a no, and keeps
	 the pending answer in this session as ``requestConfirmation(_:in:isCurrent:perform:)``
	 does. `answer` is called with ``AlertResponse/default`` when there is no
	 window to ask in, so a question whose safe answer is the default button is
	 never answered by the absence of someone to ask. */
	func requestResponse(
		_ request: AlertRequest,
		in conversation: Conversation? = nil,
		origin: PromptOrigin = .conversation,
		isCurrent: @escaping @MainActor (ServerSession) -> Bool = { _ in true },
		answer: @escaping @MainActor (ServerSession, AlertResponse) -> Void
	) {
		requestAnswer(request, in: conversation, origin: origin, isCurrent: isCurrent, unattended: .default) { session, prompt in
			answer(session, prompt.response)
		}
	}

	/** Asks a question and hands over the whole answer, with what was typed
	 into its field.

	 The pending question is kept in this session. The answer is dropped when it
	 arrives after the session started another connection, after the session
	 began terminating, after the task was cancelled, or once `isCurrent` says
	 the question no longer applies. With nobody to ask, `unattended` answers. */
	func requestAnswer(
		_ request: AlertRequest,
		in conversation: Conversation? = nil,
		origin: PromptOrigin = .conversation,
		isCurrent: @escaping @MainActor (ServerSession) -> Bool = { _ in true },
		unattended: AlertResponse,
		revealsMainWindow: Bool = true,
		answer: @escaping @MainActor (ServerSession, PromptAnswer) -> Void
	) {
		guard let prompts else {
			if !isTerminating, isCurrent(self) {
				answer(self, PromptAnswer(outcome: AlertOutcome(response: unattended, isSuppressed: false)))
			}
			return
		}
		let identifier = UUID()
		let startupIdentifier = startup.identifier
		let connection = socket?.uniqueIdentifier
		let scope = promptScope(in: conversation, origin: origin, revealsMainWindow: revealsMainWindow)
		scheduled.confirmations[identifier] = Task { [weak self, weak prompts] in
			guard let prompts else {
				self?.scheduled.confirmations.removeValue(forKey: identifier)
				return
			}
			let response = await prompts.ask(request, about: scope)
			guard let self else { return }
			defer { scheduled.confirmations.removeValue(forKey: identifier) }
			guard !Task.isCancelled, !isTerminating,
			      startup.identifier == startupIdentifier, socket?.uniqueIdentifier == connection,
			      isCurrent(self) else { return }
			answer(self, response)
		}
	}
}
