// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/// Where a question came from, which decides whether it may leave a dialog.
nonisolated enum PromptOrigin: Sendable, Equatable {
	/// From chat: a session, a typed command or a transcript or menu command
	/// about a conversation.
	case conversation
	/// From the application: a link from another app, a script file or the
	/// log writer.
	case application
	/// From inside a sheet, a window or Settings. It answers there, because a
	/// question in the conversation behind an open editor would be out of sight
	/// and split one task across two places.
	case guiSurface
}

/// The connection a question was asked on. An answer that arrives after the
/// session has connected again must not act on the new connection.
nonisolated struct PromptConnection: Sendable, Equatable {
	let startupIdentifier: UUID
	let socketIdentifier: String?
}

/// Where a question belongs, as identifiers. A snapshot: nothing in it keeps
/// a session or a conversation alive.
nonisolated struct PromptScope: Sendable, Equatable {
	/// The server session the question is about, if any.
	var sessionID: String?
	/// The conversation the question is about, if any.
	var conversationID: String?
	/// The connection the question is bound to, for a question whose answer
	/// acts on the wire.
	var connection: PromptConnection?
	var origin: PromptOrigin
	/** Whether asking brings a hidden main window forward. A question the
	 reader raised from the main window does; one the network raised in the
	 background, or one asked about whatever window is frontmost, waits where
	 it is, the same as a sheet. */
	var revealsMainWindow: Bool

	init(
		sessionID: String? = nil,
		conversationID: String? = nil,
		connection: PromptConnection? = nil,
		origin: PromptOrigin = .conversation,
		revealsMainWindow: Bool = true
	) {
		self.sessionID = sessionID
		self.conversationID = conversationID
		self.connection = connection
		self.origin = origin
		self.revealsMainWindow = revealsMainWindow
	}

	/// A question the application asks with no conversation in mind.
	static let application = PromptScope(origin: .application)
	/// A question raised from inside a sheet, a window or Settings.
	static let guiSurface = PromptScope(origin: .guiSurface)
}

/// What a question came back with.
nonisolated struct PromptAnswer: Sendable, Equatable {
	let outcome: AlertOutcome
	/// What was typed into the question's field. A secret is handed only to
	/// whoever asked.
	let text: String?

	var response: AlertResponse {
		outcome.response
	}

	init(outcome: AlertOutcome, text: String? = nil) {
		self.outcome = outcome
		self.text = text
	}

	/// The way out, for a question nobody answered.
	static func escape(for request: AlertRequest) -> PromptAnswer {
		PromptAnswer(outcome: AlertOutcome(response: request.escapeButton, isSuppressed: false))
	}
}

/** Asks the reader something, as an alert or in the conversation.

 The protocol layer says what to ask and where it belongs; which of the two the
 question appears as is the reader's choice, made in Settings, and is decided
 when the question is asked. Implemented by the application. */
@MainActor
protocol PromptPresenting: AnyObject {
	/// Suspends until the question is answered. Cancelling the task withdraws
	/// the question and answers with its Escape button.
	func ask(_ request: AlertRequest, about scope: PromptScope) async -> PromptAnswer
	/// Withdraws the questions about a session with the Escape answer. With
	/// `connectionBoundOnly`, only those bound to its connection, for a
	/// connection that ended; otherwise every one, for a session going away.
	func withdrawPrompts(inSession sessionID: String, connectionBoundOnly: Bool)
	/// Withdraws the questions about a conversation that is going away.
	func withdrawPrompts(inConversation conversationID: String)
}
