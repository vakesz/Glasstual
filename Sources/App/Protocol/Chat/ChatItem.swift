// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2018 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

class ChatItem: NSObject {
	var isActive: Bool {
		false
	}

	var isClient: Bool {
		false
	}

	var isChannel: Bool {
		false
	}

	var isPrivateMessage: Bool {
		false
	}

	var associatedChannel: Channel? {
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

	var dockUnreadCount = 0
	var nicknameHighlightCount = 0
	var treeUnreadCount = 0

	/** Weak: the world owns its clients, and an item routinely outlives the
	 client that made it while teardown finishes. */
	weak var associatedClient: Client!

	/** Weak: the window's log controller registry owns the view this item is
	 drawn into and installs itself here. An item with no window — a client
	 built by a test, an item being torn down — simply has none. */
	weak var presentation: (any ChatItemPresentation)?

	/// The preference snapshot of the client this item belongs to. An item whose
	/// client has already gone reads the declared defaults rather than the store.
	var clientPreferences: ClientPreferences {
		associatedClient?.environment.preferences ?? ClientPreferences()
	}

	var isUnread: Bool {
		treeUnreadCount > 0
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
		treeUnreadCount = 0
		associatedClient?.output?.refreshMessageCount(for: self)
	}

	func child(at _: Int) -> ChatItem? {
		nil
	}
}
