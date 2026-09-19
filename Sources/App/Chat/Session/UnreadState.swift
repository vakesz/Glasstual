// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/// What a newly printed line does to a conversation's unread and highlight
/// badges. The counters themselves live on ``ChatItem``; these decide when
/// they move and who is told.
@MainActor
extension ServerSession {
	private func conversationIsSelectedInKeyWindow(_ conversation: Conversation, output: any ServerSessionPresenting) -> Bool {
		output.isKeyWindow && output.isItemSelected(conversation)
	}

	func setHighlightState(for conversation: Conversation) {
		guard let output else { return }
		guard conversationIsSelectedInKeyWindow(conversation, output: output) == false else { return }

		conversation.nicknameHighlightCount += 1
		environment.services.updateDockBadge()
		output.reloadChatItem(conversation)
	}

	/** Raises the unread counts by `count`, which defaults to the single line
	 that is raising them.

	 A larger count belongs to the one caller that learns about several unread
	 lines at once: a read marker the server sends names a point, and everything
	 a person said after it is unread. */
	func setUnreadState(for conversation: Conversation, isHighlight: Bool = false, count: Int = 1) {
		assert(count >= 1, "An unread badge counts at least one line")

		let count = max(1, count)

		guard let output else { return }
		guard conversationIsSelectedInKeyWindow(conversation, output: output) == false else { return }

		/* A direct conversation always counts on the dock badge; a channel does so
		 only when the user asked for public messages to be counted there. */
		if conversation.isChannel == false || environment.settings.displayPublicMessageCountOnDockBadge {
			conversation.dockUnreadCount += count
			environment.services.updateDockBadge()
		}

		conversation.unreadCount += count

		if isHighlight || conversation.config.showsUnreadCount {
			output.refreshMessageCount(for: conversation)
		}
	}
}
