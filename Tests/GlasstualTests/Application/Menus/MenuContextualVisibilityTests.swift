// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
@testable import Glasstual
import Testing

/// HIG Context menus: hide unavailable items, don't dim them; Cut, Copy and
/// Paste excepted. The menu bar keeps dimming.
@MainActor
@Suite("Context menu visibility")
struct MenuContextualVisibilityTests {
	private func item(_ command: MenuCommand?) -> NSMenuItem {
		let item = NSMenuItem(title: "", action: nil, keyEquivalent: "")
		item.command = command
		return item
	}

	@Test("A context menu leaves out what does not apply; the menu bar dims it")
	func unavailableItemsAreHiddenOnlyInContextMenus() {
		let ban = item(.ban)
		MenuContextualVisibility.settle(ban, isAvailable: false, isContextual: true)
		#expect(ban.isHidden)

		MenuContextualVisibility.settle(ban, isAvailable: false, isContextual: false)
		#expect(ban.isHidden == false)

		MenuContextualVisibility.settle(ban, isAvailable: true, isContextual: true)
		#expect(ban.isHidden == false)
	}

	@Test("Cut, Copy and Paste stay in a context menu, dimmed")
	func clipboardCommandsStay() {
		for command in [MenuCommand.cut, .copy, .paste] {
			let clipboard = item(command)
			MenuContextualVisibility.settle(clipboard, isAvailable: false, isContextual: true)
			#expect(clipboard.isHidden == false)
		}
	}

	/// Connect and Disconnect are one command in two states; the validator's
	/// own choice of which to show survives in the menu bar.
	@Test("A paired command keeps the state its validator hid")
	func pairedCommandsKeepTheirValidatorState() {
		let disconnect = item(.disconnect)
		disconnect.isHidden = true
		MenuContextualVisibility.settle(disconnect, isAvailable: true, isContextual: false)
		#expect(disconnect.isHidden)

		let connect = item(.connect)
		connect.isHidden = false
		MenuContextualVisibility.settle(connect, isAvailable: false, isContextual: true)
		#expect(connect.isHidden)
	}

	@Test("Only separators between two visible groups are kept")
	func separatorsBetweenVisibleGroups() {
		typealias Entry = MenuContextualVisibility.Entry
		let entries: [Entry] = [.separator, .item, .separator, .hidden, .separator, .item, .separator, .hidden]
		#expect(MenuContextualVisibility.visibleSeparatorIndices(in: entries) == [2])
		#expect(MenuContextualVisibility.visibleSeparatorIndices(in: [.hidden, .separator, .item]) == [])
		#expect(MenuContextualVisibility.visibleSeparatorIndices(in: [.item, .separator, .separator, .item]) == [1])
	}

	@Test("A popped-up menu is contextual; the menu bar and the Dock menu are not")
	func contextualMenus() {
		let bar = NSMenu(title: "Bar")
		let dock = NSMenu(title: "")
		let channel = NSMenu(title: "Channel")
		let holder = NSMenuItem(title: "Channel", action: nil, keyEquivalent: "")
		holder.submenu = channel
		bar.addItem(holder)
		let popup = NSMenu(title: "")

		#expect(MenuContextualVisibility.isContextual(channel, menuBar: bar, dock: dock) == false)
		#expect(MenuContextualVisibility.isContextual(dock, menuBar: bar, dock: dock) == false)
		#expect(MenuContextualVisibility.isContextual(popup, menuBar: bar, dock: dock))
	}

	@Test("Hiding redundant separators leaves none leading, trailing or doubled")
	func hideRedundantSeparators() {
		let menu = NSMenu(title: "")
		let first = item(.whois)
		let hidden = item(.ban)
		hidden.isHidden = true
		let last = item(.kick)
		for entry in [NSMenuItem.separator(), first, .separator(), hidden, .separator(), last, .separator()] {
			menu.addItem(entry)
		}

		MenuContextualVisibility.hideRedundantSeparators(in: menu)

		#expect(menu.items.filter { $0.isHidden == false }.map(\.isSeparatorItem) == [false, true, false])
	}
}
