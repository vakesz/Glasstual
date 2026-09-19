// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit

/// Which rows a navigation command walks: every row, the active ones, or the
/// ones carrying unread messages.
enum SidebarNavigationMovement: UInt {
	case all
	case active
	case unread
}

/// Which rows a navigation command is allowed to land on.
private enum SidebarNavigationSelection {
	case any
	/// Any conversation row: a channel, a one-to-one conversation, the console
	/// or a DCC chat.
	case conversation
	case server
}

/// Moving the selection through the sidebar: the twelve Navigation menu
/// commands, and the walk they share.
extension MainWindow {
	/** Moves the selection to the next row that qualifies.

	 `rows` is rotated so the walk starts one past the current selection and
	 comes back round to it, and the first row that is both of the right kind
	 and in the right state wins. A selection that is not in `rows` -- nothing
	 selected, or a row the filter has taken out of the list -- has nowhere to
	 walk from, so nothing moves. */
	private func navigate(
		_ rows: [ChatItem],
		from startingPoint: Int,
		isMovingDown: Bool,
		navigationType: SidebarNavigationMovement,
		selectionType: SidebarNavigationSelection
	) {
		guard rows.indices.contains(startingPoint) else { return }
		let count = rows.count
		let rotated = (1 ..< count).lazy.map { offset -> ChatItem in
			let position = isMovingDown ? startingPoint + offset : startingPoint - offset + count
			return rows[position % count]
		}
		guard let destination = rotated.first(where: {
			Self.item($0, is: selectionType) && Self.item($0, matches: navigationType)
		}) else { return }
		select(destination)
	}

	private static func item(_ item: ChatItem, is selectionType: SidebarNavigationSelection) -> Bool {
		switch selectionType {
		case .any:
			true
		case .conversation:
			item.isChannel || item.isDirect || item.associatedConversation?.isDirectChat == true
		case .server:
			item.isSession
		}
	}

	private static func item(_ item: ChatItem, matches navigationType: SidebarNavigationMovement) -> Bool {
		switch navigationType {
		case .all:
			true
		case .active:
			item.isActive
		case .unread:
			item.isUnread
		}
	}

	func navigateConversationEntries(_ isMovingDown: Bool, withNavigationType navigationType: SidebarNavigationMovement) {
		if SettingsKeys.Appearance.conversationNavigationIsServerSpecific.value {
			navigateConversationsWithinServerScope(isMovingDown, navigationType: navigationType)
		} else {
			navigateConversationsOutsideServerScope(isMovingDown, navigationType: navigationType)
		}
	}

	private func navigateConversationsOutsideServerScope(
		_ isMovingDown: Bool,
		navigationType: SidebarNavigationMovement
	) {
		let rows = sidebar.selectableItems
		navigate(
			rows,
			from: sidebar.row(forItem: selectedItem),
			isMovingDown: isMovingDown,
			navigationType: navigationType,
			selectionType: .conversation
		)
	}

	private func navigateConversationsWithinServerScope(
		_ isMovingDown: Bool,
		navigationType: SidebarNavigationMovement
	) {
		guard let selectedSession else { return }
		var rows = selectedItem.flatMap { sidebar.items(inContainingGroupOf: $0) } ?? []
		rows.append(selectedSession)
		navigate(
			rows,
			from: rows.firstIndex { $0 === selectedItem } ?? -1,
			isMovingDown: isMovingDown,
			navigationType: navigationType,
			selectionType: .conversation
		)
	}

	func navigateServerEntries(_ isMovingDown: Bool, withNavigationType navigationType: SidebarNavigationMovement) {
		let rows = sidebar.groupItems
		navigate(
			rows,
			from: rows.firstIndex { $0 === selectedSession } ?? -1,
			isMovingDown: isMovingDown,
			navigationType: navigationType,
			selectionType: .server
		)
	}

	func navigateToNextEntry(_ isMovingDown: Bool) {
		let rows = sidebar.selectableItems
		navigate(
			rows,
			from: sidebar.row(forItem: selectedItem),
			isMovingDown: isMovingDown,
			navigationType: .all,
			selectionType: .any
		)
	}

	func selectPreviousConversation(_: NSEvent?) {
		navigateConversationEntries(false, withNavigationType: .all)
	}

	func selectNextConversation(_: NSEvent?) {
		navigateConversationEntries(true, withNavigationType: .all)
	}

	func selectPreviousUnreadConversation(_: NSEvent?) {
		navigateConversationEntries(false, withNavigationType: .unread)
	}

	func selectNextUnreadConversation(_: NSEvent?) {
		navigateConversationEntries(true, withNavigationType: .unread)
	}

	func selectPreviousActiveConversation(_: NSEvent?) {
		navigateConversationEntries(false, withNavigationType: .active)
	}

	func selectNextActiveConversation(_: NSEvent?) {
		navigateConversationEntries(true, withNavigationType: .active)
	}

	func selectPreviousServer(_: NSEvent?) {
		navigateServerEntries(false, withNavigationType: .all)
	}

	func selectNextServer(_: NSEvent?) {
		navigateServerEntries(true, withNavigationType: .all)
	}

	func selectPreviousActiveServer(_: NSEvent?) {
		navigateServerEntries(false, withNavigationType: .active)
	}

	func selectNextActiveServer(_: NSEvent?) {
		navigateServerEntries(true, withNavigationType: .active)
	}

	func selectPreviousSelection(_: NSEvent?) {
		selectPreviousItem()
	}

	func selectNextWindow(_: NSEvent?) {
		navigateToNextEntry(true)
	}

	func selectPreviousWindow(_: NSEvent?) {
		navigateToNextEntry(false)
	}
}
