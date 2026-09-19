// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2018 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

class ChatItem: NSObject {
	var isActive: Bool {
		false
	}

	var isSession: Bool {
		false
	}

	var isChannel: Bool {
		false
	}

	var isDirect: Bool {
		false
	}

	var associatedConversation: Conversation? {
		nil
	}

	var label: String {
		""
	}

	var name: String {
		""
	}

	var uniqueIdentifier: String {
		""
	}

	var numberOfChildren: Int {
		0
	}

	/** This item's transcript file. Both subclasses write one, so the file and
	 the session banner it holds open are owned here rather than twice over. */
	let transcriptLog = TranscriptFileLog()

	/// Unread messages as the Dock badge counts them, which follows the reader's
	/// badge settings rather than the sidebar's.
	var dockUnreadCount = 0
	var nicknameHighlightCount = 0
	/// Unread messages as the sidebar row and the spotlight list show them.
	var unreadCount = 0

	/** Weak: the chat session owns its sessions, and an item routinely outlives the
	 session that made it while teardown finishes. */
	weak var associatedSession: ServerSession?

	/** Weak: the window's transcript registry owns the view this item is drawn
	 into and installs itself here. An item with no window — a session built by a
	 test, an item being torn down — simply has none. */
	weak var presentation: (any ChatItemPresenting)?

	/// The setting snapshot of the session this item belongs to. An item whose
	/// session has already gone reads the declared defaults rather than the store.
	var chatSettings: ChatSettings {
		associatedSession?.environment.settings ?? ChatSettings()
	}

	var isUnread: Bool {
		unreadCount > 0
	}

	/// Clears the counts and redraws the badge that showed them. `setUnreadState`
	/// asks for the redraw when it raises a count, so the reset does the same
	/// rather than leaving a stale badge until something else redraws the row.
	/// Invalidates unread completions queued before an explicit mark-read.
	private(set) var readStateGeneration: UInt64 = 0

	func resetState() {
		readStateGeneration &+= 1
		dockUnreadCount = 0
		nicknameHighlightCount = 0
		unreadCount = 0
		associatedSession?.output?.refreshMessageCount(for: self)
	}

	func child(at _: Int) -> ChatItem? {
		nil
	}
}
