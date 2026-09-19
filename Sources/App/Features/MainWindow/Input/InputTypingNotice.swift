// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
import CocoaExtensions

/** Who is typing, in both directions.

 Outbound: what the reader types tells the conversation they are typing, and
 leaving that conversation tells it they stopped. Inbound: other people's
 notices are the row drawn over the message field. Neither is the text view's
 business -- the field only reports that its text changed -- and the conversation
 is asked for per event rather than held, so the policy can be exercised against
 a source that is not a window's selection. */
@MainActor
final class InputTypingNotice {
	/// The row the notices are drawn in, which also carries the reply banner.
	private let accessoryModel: InputAccessoryModel
	/// Which conversation the notices belong to, asked for per event: the
	/// selection moves under this, and an answer held from the last one would
	/// address the conversation the reader has just left.
	private let selectedConversation: @MainActor () -> Conversation?
	/// The conversation the reader was last typing in, so it can be told they
	/// stopped after the selection has already moved off it.
	private var typingConversation: Conversation?
	/// The typing tracker and the window's selection, while the field is in a
	/// window.
	private let notifications = NotificationSubscriptions()
	private var isObserving = false

	init(
		accessoryModel: InputAccessoryModel,
		selectedConversation: @escaping @MainActor () -> Conversation?
	) {
		self.accessoryModel = accessoryModel
		self.selectedConversation = selectedConversation
	}

	func setObserved(_ observed: Bool) {
		guard isObserving != observed else {
			return
		}

		isObserving = observed

		guard observed else {
			notifications.cancelAll()
			return
		}

		notifications.observe(.typingTrackerDidChange) { [weak self] notification in
			self?.typingStateDidChange(notification)
		}
		notifications.observe(.mainWindowSelectionChanged) { [weak self] _ in
			self?.selectionDidChange()
		}
	}

	/// The reader's own text changed. A command is not a message, so a line that
	/// starts with a slash announces nothing.
	func noteTextChanged(_ text: String) {
		guard let conversation = selectedConversation(), let session = conversation.associatedSession else {
			return
		}

		session.noteLocalUserTyping(text, in: conversation)
		typingConversation = text.isEmpty || text.hasPrefix("/") ? nil : conversation
	}

	/** Tells the conversation the reader was typing in that they stopped, unless
	 it is `conversation`.

	 The window calls this when the selection changes and before it refills the
	 field. A notice that waited for the selection notification arrived after the
	 refill had already recorded the new conversation as the one being typed in,
	 so the old one never heard that typing stopped. */
	func finish(unlessIn conversation: Conversation?) {
		guard let typingConversation, typingConversation !== conversation else { return }
		typingConversation.associatedSession?.localUserClearedText(in: typingConversation)
		self.typingConversation = nil
	}

	private func typingStateDidChange(_ notification: Notification) {
		guard let conversation = notification.userInfo?[typingTrackerConversationKey] as? Conversation,
		      conversation === selectedConversation()
		else {
			return
		}

		updateTypingRow()
	}

	/** The conversation showing in the window changed.

	 Everything the row was carrying belonged to the conversation that has just
	 left: the notice the reader owed it, and the reply they had started in it.
	 Both are dropped here rather than in the text view, which is what keeps the
	 row and the selection from disagreeing for a turn. */
	private func selectionDidChange() {
		finish(unlessIn: selectedConversation())
		accessoryModel.hideReply()
		updateTypingRow()
	}

	private func updateTypingRow() {
		let conversation = selectedConversation()
		var nicknames: [String] = []

		if let conversation, conversation.isConsole == false {
			nicknames = conversation.associatedSession?.typingTracker.typingNicknames(in: conversation) ?? []
		}

		accessoryModel.setTypingNicknames(nicknames)
	}
}
