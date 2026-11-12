// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit

/** What the reader needs to delete a message: whether the menu offers it, and
 the question asked before the server is told.

 The server decides in the end. This only declines to offer what cannot work:
 a server without the capability, and a message that is neither the reader's
 nor in a channel they operate. A refusal that still comes back is printed in
 the conversation by the session. */
@MainActor
enum TranscriptMessageDeletion {
	static func isOffered(
		forMessageBy nickname: String?,
		in conversation: Conversation,
		on session: ServerSession
	) -> Bool {
		guard session.supportsMessageRedaction, conversation.isConsole == false else { return false }
		if let nickname, nickname.isEmpty == false, session.nicknameIsMyself(nickname) {
			return true
		}
		guard conversation.isChannel, let member = conversation.findMember(session.userNickname) else {
			return false
		}
		return member.isOp
	}

	/// The question asked before a message is deleted, with a field for the
	/// reason. The default deletes, so no button is on Return; Escape cancels.
	static var request: AlertRequest {
		AlertRequest(
			title: String(localized: .Transcript.deleteMessageTitle),
			body: String(localized: .Transcript.deleteMessageBody),
			defaultButton: String(localized: .Transcript.deleteMessageConfirm),
			alternateButton: PromptStrings.Action.cancel,
			destructiveButton: .default,
			style: .warning,
			field: .text(
				placeholder: String(localized: .Transcript.deleteMessageReasonPlaceholder), initialValue: "", isRequired: false
			),
			keywords: [.default: .delete, .alternate: .cancel]
		)
	}

	/** Asks whether to delete the message, and why.

	 Returns the reason the reader typed, which is empty for none, or `nil` when
	 they backed out. */
	static func confirm(in conversation: Conversation, on session: ServerSession) async -> String? {
		let answer = await Alerts.ask(request, about: session.promptScope(in: conversation, boundToConnection: false))
		guard answer.response == .default else { return nil }
		return answer.text ?? ""
	}
}

/// What a "Delete Message" menu item stands for. The session and conversation
/// are held weakly: the menu can outlive either.
final class TranscriptMessageDeletionRequest: NSObject {
	let messageIdentifier: String
	weak var conversation: Conversation?
	weak var session: ServerSession?

	init(messageIdentifier: String, conversation: Conversation, session: ServerSession) {
		self.messageIdentifier = messageIdentifier
		self.conversation = conversation
		self.session = session
	}
}
