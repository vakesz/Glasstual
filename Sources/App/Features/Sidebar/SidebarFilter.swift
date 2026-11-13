// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/// Attention filters compose with name search without changing the open conversation.
enum SidebarFilter: String, CaseIterable, Identifiable {
	case all
	case unread
	case mentions

	var id: Self {
		self
	}

	var title: LocalizedStringResource {
		switch self {
		case .all: .Sidebar.filterAll
		case .unread: .Sidebar.filterUnread
		case .mentions: .Sidebar.filterMentions
		}
	}

	func matches(_ conversation: Conversation) -> Bool {
		switch self {
		case .all: true
		case .unread: conversation.unreadCount > 0
		case .mentions: conversation.nicknameHighlightCount > 0 && !conversation.config.ignoreHighlights
		}
	}
}
