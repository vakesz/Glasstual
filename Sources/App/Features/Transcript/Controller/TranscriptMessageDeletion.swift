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

	/** Asks whether to delete the message, and why.

	 Returns the reason the reader typed, which is empty for none, or `nil` when
	 they backed out. A sheet on the transcript's window when there is one. */
	static func confirm(in window: NSWindow?) async -> String? {
		let alert = NSAlert()
		alert.alertStyle = .warning
		alert.messageText = String(localized: .Transcript.deleteMessageTitle)
		alert.informativeText = String(localized: .Transcript.deleteMessageBody)
		alert.addButton(withTitle: String(localized: .Transcript.deleteMessageConfirm)).hasDestructiveAction = true
		alert.addButton(withTitle: PromptStrings.Action.cancel)

		let placeholder = String(localized: .Transcript.deleteMessageReasonPlaceholder)
		let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
		field.placeholderString = placeholder
		field.setAccessibilityLabel(placeholder)
		alert.accessoryView = field

		let response: NSApplication.ModalResponse = if let window {
			await alert.beginSheetModal(for: window)
		} else {
			alert.runModal()
		}
		guard response == .alertFirstButtonReturn else { return nil }
		return field.stringValue
	}
}

/// What a "Delete Message" menu item stands for. The session and conversation
/// are held weakly: the menu can outlive either.
final class TranscriptMessageDeletionRequest: NSObject {
	let messageIdentifier: String
	weak var conversation: Conversation?
	weak var session: ServerSession?
	weak var window: NSWindow?

	init(messageIdentifier: String, conversation: Conversation, session: ServerSession, window: NSWindow?) {
		self.messageIdentifier = messageIdentifier
		self.conversation = conversation
		self.session = session
		self.window = window
	}
}
