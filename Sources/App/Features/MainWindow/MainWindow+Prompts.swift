// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit

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
}
