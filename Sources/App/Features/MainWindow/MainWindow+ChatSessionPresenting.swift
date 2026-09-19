// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit

// MARK: - ChatSession observer

/** The window draws what the chat session publishes. Nothing here reaches
 back into the IRC layer; every entry point is an event the chat session posted. */
extension MainWindow: ChatSessionPresenting {
	func chatSessionWillBeginBulkUpdate(_: ChatSession) {
		sidebar?.beginUpdates()
	}

	func chatSessionDidEndBulkUpdate(_: ChatSession) {
		sidebar?.endUpdates()
	}

	func chatSession(_: ChatSession, didAddSession session: ServerSession, at _: Int) {
		/* The views have to exist before the row that shows them does. */
		transcriptControllers.registerSidebar(of: session)
		sidebar?.setNeedsRefresh()
	}

	func chatSession(_: ChatSession, didRemoveSession session: ServerSession) {
		sidebar?.itemWasRemoved(session)
		transcriptControllers.forgetSidebar(of: session)
	}

	func chatSession(_: ChatSession, didMoveSessionFrom _: Int, to _: Int) {
		sidebar?.setNeedsRefresh()
	}

	func chatSession(_: ChatSession, didAddConversation conversation: Conversation, on _: ServerSession, at _: Int) {
		transcriptControllers.controller(for: conversation)
		sidebar?.setNeedsRefresh()
	}

	func chatSession(_: ChatSession, didRemoveConversation conversation: Conversation, on _: ServerSession) {
		sidebar?.itemWasRemoved(conversation)
		transcriptControllers.forget(conversation)
	}

	func chatSession(_: ChatSession, didMoveConversationOn _: ServerSession, from _: Int, to _: Int) {
		sidebar?.setNeedsRefresh()
	}

	func chatSession(_: ChatSession, requestsSelectionOf item: ChatItem) {
		select(item)
	}

	func chatSession(_: ChatSession, requestsDeselectionOf item: ChatItem) {
		deselect(item)
	}

	func chatSession(_: ChatSession, requestsGroupDeselectionOf item: ChatItem) {
		deselectGroup(item)
	}

	func chatSessionRequestsSelectionAdjustment(_: ChatSession) {
		adjustSelection()
	}

	func chatSessionListDidChange(_: ChatSession) {
		reloadLoadingScreen()
	}
}
