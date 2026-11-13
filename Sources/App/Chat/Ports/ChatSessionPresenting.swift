// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/** What the chat session tells the user interface about the shape of the
 sidebar.

 The chat session owns the server sessions and their conversations; it does not
 own the sidebar, the navigation menu or the selection. It publishes these
 events instead, and the window layer decides what to draw. Every requirement
 has a default no-op, so a conformer implements only the events it cares
 about. */
@MainActor
protocol ChatSessionPresenting: AnyObject {
	/// A run of add/remove events follows; observers may batch their redraws.
	func chatSessionWillBeginBulkUpdate(_ chatSession: ChatSession)
	func chatSessionDidEndBulkUpdate(_ chatSession: ChatSession)

	func chatSession(_ chatSession: ChatSession, didAddSession session: ServerSession, at index: Int)
	func chatSession(_ chatSession: ChatSession, didRemoveSession session: ServerSession)
	func chatSession(_ chatSession: ChatSession, didMoveSessionFrom oldIndex: Int, to newIndex: Int)

	func chatSession(
		_ chatSession: ChatSession,
		didAddConversation conversation: Conversation,
		on session: ServerSession,
		at index: Int
	)
	func chatSession(_ chatSession: ChatSession, didRemoveConversation conversation: Conversation, on session: ServerSession)
	func chatSession(
		_ chatSession: ChatSession,
		didMoveConversationOn session: ServerSession,
		from oldIndex: Int,
		to newIndex: Int
	)

	func chatSession(_ chatSession: ChatSession, requestsSelectionOf item: ChatItem)
	func chatSession(_ chatSession: ChatSession, requestsDeselectionOf item: ChatItem)
	func chatSession(_ chatSession: ChatSession, requestsGroupDeselectionOf item: ChatItem)
	func chatSessionRequestsSelectionAdjustment(_ chatSession: ChatSession)

	/// The set of sessions changed; anything keyed off "are there any sessions"
	/// — the loading screen, for one — should refresh.
	func chatSessionListDidChange(_ chatSession: ChatSession)
	/// The sidebar's rows changed: the flattened session/conversation list the
	/// sidebar and the navigation menu are both built from.
	func chatSessionSidebarDidChange(_ chatSession: ChatSession)
	/// Settings were applied; observers holding derived state should reload.
	func chatSessionSettingsDidChange(_ chatSession: ChatSession)
}

extension ChatSessionPresenting {
	func chatSessionWillBeginBulkUpdate(_: ChatSession) {}
	func chatSessionDidEndBulkUpdate(_: ChatSession) {}
	func chatSession(_: ChatSession, didAddSession _: ServerSession, at _: Int) {}
	func chatSession(_: ChatSession, didRemoveSession _: ServerSession) {}
	func chatSession(_: ChatSession, didMoveSessionFrom _: Int, to _: Int) {}
	func chatSession(_: ChatSession, didAddConversation _: Conversation, on _: ServerSession, at _: Int) {}
	func chatSession(_: ChatSession, didRemoveConversation _: Conversation, on _: ServerSession) {}
	func chatSession(_: ChatSession, didMoveConversationOn _: ServerSession, from _: Int, to _: Int) {}
	func chatSession(_: ChatSession, requestsSelectionOf _: ChatItem) {}
	func chatSession(_: ChatSession, requestsDeselectionOf _: ChatItem) {}
	func chatSession(_: ChatSession, requestsGroupDeselectionOf _: ChatItem) {}
	func chatSessionRequestsSelectionAdjustment(_: ChatSession) {}
	func chatSessionListDidChange(_: ChatSession) {}
	func chatSessionSidebarDidChange(_: ChatSession) {}
	func chatSessionSettingsDidChange(_: ChatSession) {}
}

/** The list of conformers. Entries are weak: a conformer is a window or a menu
 controller whose lifetime the chat session has no say in, and a dead entry is
 dropped once an event has been delivered past it.

 Delivery walks a snapshot rather than the list itself. An observer that
 registered another from inside an event was writing to the list while the
 delivery loop still held it for writing — an exclusivity violation — and the
 loop then put back the list it had started with, losing the registration. */
@MainActor
struct ChatSessionPresenterList {
	private struct Entry {
		weak var observer: (any ChatSessionPresenting)?
	}

	private var entries: [Entry] = []

	mutating func add(_ observer: any ChatSessionPresenting) {
		pruneReleased()
		guard entries.contains(where: { $0.observer === observer }) == false else { return }
		entries.append(Entry(observer: observer))
	}

	mutating func remove(_ observer: any ChatSessionPresenting) {
		entries.removeAll { $0.observer == nil || $0.observer === observer }
	}

	/// The observers still alive, in the order they registered.
	var liveObservers: [any ChatSessionPresenting] {
		entries.compactMap(\.observer)
	}

	/// Forgets the entries whose observer has gone.
	mutating func pruneReleased() {
		entries.removeAll { $0.observer == nil }
	}
}
