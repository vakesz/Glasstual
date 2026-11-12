// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
import CocoaExtensions

// MARK: - Questions in the conversation

extension MainWindow {
	/** The chat item a question about `scope` appears in.

	 A question about a conversation appears in it, and one about a session in
	 its console. A question the application asks with no conversation in mind
	 appears wherever the reader is. `nil` when none of those exists, and the
	 question opens as an alert instead. */
	func promptAnchor(for scope: PromptScope) -> String? {
		if let conversationID = scope.conversationID, let sessionID = scope.sessionID,
		   let conversation = chatSession?.findConversation(withId: conversationID, onSessionWithId: sessionID)
		{
			return conversation.uniqueIdentifier
		}
		if let sessionID = scope.sessionID {
			return chatSession?.findSession(withId: sessionID)?.uniqueIdentifier
		}
		return selectedItem?.uniqueIdentifier
	}

	/// Brings the conversation a question waits in on screen.
	func showPromptAnchor(_ itemID: String) {
		guard let item = chatSession?.findItem(withId: itemID) else { return }
		select(item)
	}

	/** Returns the keyboard to the message field after a card was answered,
	 and says so when the answer came too late to count. */
	func promptWasAnswered(_ prompt: PendingPrompt, result: PromptAnswerResult) {
		let registry = AppServices.promptRegistry
		switch result {
		case .answered:
			registry.feedback = nil
		case .notPending:
			registry.feedback = PromptFeedback(
				itemID: prompt.route.itemID, text: String(localized: .InlinePrompts.notPending(prompt.number))
			)
		case .connectionChanged:
			registry.feedback = PromptFeedback(
				itemID: prompt.route.itemID, text: String(localized: .InlinePrompts.connectionChanged(prompt.number))
			)
		}
		inputTextField.focus()
	}

	/** Tells VoiceOver a question appeared in the conversation. One in the
	 conversation on screen is read at once; one elsewhere says where it is,
	 at a lower priority. */
	func announcePrompt(_ prompt: PendingPrompt) {
		let request = prompt.request
		let choices = request.responses.compactMap(request.title(for:)).formatted(.list(type: .or))
		let text: String
		let priority: NSAccessibilityPriorityLevel
		if let anchor = prompt.route.itemID, anchor != selectedItem?.uniqueIdentifier,
		   let item = chatSession?.findItem(withId: anchor)
		{
			text = String(localized: .InlinePrompts.announcementElsewhere(
				prompt.number, item.label.isEmpty ? item.name : item.label, request.title, choices
			))
			priority = .medium
		} else {
			text = String(localized: .InlinePrompts.announcement(prompt.number, request.title, choices))
			priority = .high
		}
		NSAccessibility.post(element: NSApplication.shared, notification: .announcementRequested, userInfo: [
			.announcement: text,
			.priority: priority.rawValue,
		])
	}
}
