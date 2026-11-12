// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit

/** Whether an unavailable command is dimmed or left out.

 The menu bar dims what does not apply, so its menus keep their shape and stay
 learnable. A context menu is about the one thing under the pointer, so it
 leaves out what that thing cannot do; Cut, Copy and Paste are the exception
 and stay, dimmed, where people expect them (HIG Context menus). */
@MainActor
enum MenuContextualVisibility {
	/// The commands a context menu dims rather than leaves out.
	static let dimmedCommands: Set<MenuCommand> = [.cut, .copy, .paste]

	/// Two states of one command. Their validator already hides the state that
	/// does not apply, so only a contextual menu adds to that.
	static let pairedCommands: Set<MenuCommand> = [
		.connect, .connectWithoutProxy, .disconnect,
		.joinChannel, .leaveChannel,
		.muteUser, .unmuteUser,
	]

	/** Whether `menu` is popped up rather than hung in the menu bar.

	 A menu whose outermost menu is neither the menu bar nor the Dock menu is
	 one a view built for a click: the transcript's copies of the shared
	 menus, and the member menu. */
	static func isContextual(_ menu: NSMenu?, menuBar: NSMenu?, dock: NSMenu?) -> Bool {
		guard var root = menu else { return false }
		while let parent = root.supermenu {
			root = parent
		}
		return root !== menuBar && root !== dock
	}

	/// Whether a contextual menu leaves out an item with this command when it
	/// does not apply.
	static func hidesWhenUnavailable(_ command: MenuCommand?) -> Bool {
		guard let command else { return true }
		return dimmedCommands.contains(command) == false && command.isTopLevelMenu == false
	}

	/** Settles `item`'s visibility once its validator has answered.

	 A paired command keeps the hidden state its validator gave it; every other
	 item is shown unless it is contextual and unavailable. */
	static func settle(_ item: NSMenuItem, isAvailable: Bool, isContextual: Bool) {
		let hidesForContext = isContextual && isAvailable == false && hidesWhenUnavailable(item.command)
		if item.command.map(pairedCommands.contains) == true {
			if hidesForContext {
				item.isHidden = true
			}
		} else {
			item.isHidden = hidesForContext
		}
	}

	/** Hides the separators that would no longer separate anything: leading,
	 trailing and doubled ones left behind by hidden items. */
	static func hideRedundantSeparators(in menu: NSMenu) {
		let visible = visibleSeparatorIndices(in: menu.items.map {
			$0.isSeparatorItem ? Entry.separator : $0.isHidden ? .hidden : .item
		})
		for (index, item) in menu.items.enumerated() where item.isSeparatorItem {
			item.isHidden = visible.contains(index) == false
		}
	}

	/// What a menu row is, for working out which separators to keep.
	enum Entry: Equatable {
		case item
		case hidden
		case separator
	}

	/// The indices of the separators that sit between two visible groups.
	static func visibleSeparatorIndices(in entries: [Entry]) -> Set<Int> {
		var kept: Set<Int> = []
		var pending: Int?
		var hasVisibleItem = false
		for (index, entry) in entries.enumerated() {
			switch entry {
			case .hidden:
				continue
			case .separator:
				if hasVisibleItem, pending == nil {
					pending = index
				}
			case .item:
				if let separator = pending {
					kept.insert(separator)
					pending = nil
				}
				hasVisibleItem = true
			}
		}
		return kept
	}
}
