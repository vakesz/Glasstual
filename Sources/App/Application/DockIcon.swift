// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit

/** The Dock tile's badge: the standard label, so the system draws it and the
 accessibility and appearance settings apply without this file knowing them.

 One number stands for everything that wants attention. A conversation counts
 its unread messages as the badge settings allow, and its highlights always;
 a highlighted message is also an unread one, so the larger of the two is that
 conversation's share rather than their sum. */
enum DockIcon {
	private static let maximumDisplayedCount: UInt = 9999

	@MainActor private static var cachedCount = -1

	@MainActor static func updateDockIcon() {
		/* Turning the setting off has to clear whatever is already drawn:
		 this is the only thing the setting-change path calls. */
		guard SettingsKeys.Notifications.displayDockBadge.value else {
			drawWithoutCount()
			return
		}

		guard let chatSession = AppServices.chatSession else { return }

		var total: UInt = 0
		for session in chatSession.sessions {
			for conversation in session.conversationList {
				total += attentionCount(for: conversation)
			}
		}

		draw(withCount: total)
	}

	/// What one conversation adds to the badge.
	@MainActor static func attentionCount(for conversation: Conversation) -> UInt {
		let messages = conversation.config.pushNotifications ? conversation.dockUnreadCount : 0
		return UInt(max(messages, conversation.nicknameHighlightCount, 0))
	}

	@MainActor static func resetCachedCount() {
		cachedCount = -1
	}

	@MainActor static func drawWithoutCount() {
		draw(withCount: 0)
	}

	@MainActor static func draw(withCount count: UInt) {
		guard cachedCount != Int(count) else { return }
		cachedCount = Int(count)

		NSApp.dockTile.badgeLabel = count == 0 ? nil : badgeString(forCount: count)
	}

	static func badgeString(forCount count: UInt) -> String {
		if count > maximumDisplayedCount {
			return String(localized: .MainWindow.dockIconBadgeShown(
				maximumDisplayedCount.formatted(.number)
			))
		}
		return count.formatted(.number)
	}
}
