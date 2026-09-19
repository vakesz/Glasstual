// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
import SwiftUI

/// The rows a contextual menu was opened on, and the resolver that answers
/// commands against them.
struct MenuTargetContext {
	let resolver: MenuContextResolver
	let context: MenuContextResolver.MenuContext

	init(coordinator: MenuActionController, item: ChatItem?) {
		resolver = coordinator.context
		context = .sidebarItem(item)
	}

	init(coordinator: MenuActionController, members: [Member]) {
		resolver = coordinator.context
		context = .members(members)
	}
}

/// Renders the app's typed command menu graph as native SwiftUI menu content.
/// The `NSMenu` remains the macOS command boundary used by the menu bar and
/// responder chain; no AppKit view is hosted for contextual presentation.
///
/// The menus handed here are the shared AppKit ones, whose validators express
/// availability through `isHidden` as often as through enablement. They are
/// therefore validated once, up front, and snapshotted — the body then only
/// reads that snapshot, so drawing the menu never mutates AppKit state.
struct MenuContentView: View {
	private let entries: [MenuItemSnapshot]
	private let prepareSelection: () -> Void

	init(menu: NSMenu, context: MenuTargetContext? = nil, prepareSelection: @escaping () -> Void) {
		entries = MenuItemSnapshot.validating(menu, context: context)
		self.prepareSelection = prepareSelection
	}

	private init(entries: [MenuItemSnapshot], prepareSelection: @escaping () -> Void) {
		self.entries = entries
		self.prepareSelection = prepareSelection
	}

	var body: some View {
		ForEach(entries) { entry in
			MenuItemView(entry: entry, prepareSelection: prepareSelection)
		}
	}

	fileprivate static func submenu(_ entries: [MenuItemSnapshot], _ prepareSelection: @escaping () -> Void) -> Self {
		Self(entries: entries, prepareSelection: prepareSelection)
	}
}

/// One item AppKit left visible, with everything the SwiftUI menu draws or
/// sends read at validation time.
struct MenuItemSnapshot: Identifiable {
	enum Content {
		case separator
		case command(action: Selector?, target: AnyObject?)
		case submenu([MenuItemSnapshot])
	}

	/// The menu item's own identity: two items can share a command (the same
	/// action appears in the menu bar and in a context menu) and an index
	/// changes as soon as validation hides a neighbour.
	let id: ObjectIdentifier
	/// The item the action is sent *from*, and nothing else: the snapshot exists
	/// so that drawing a menu never reads live AppKit state, and
	/// `NSApp.sendAction(_:to:from:)` needs a sender.
	private let sender: NSMenuItem
	/// What the item issues, read at validation time like everything else here.
	let command: MenuCommand?
	let title: String
	let isEnabled: Bool
	/// Whether the command is currently in force. AppKit draws this as a tick;
	/// SwiftUI draws it by making the row a toggle.
	let isOn: Bool
	let shortcut: KeyboardShortcut?
	let content: Content
	private let context: MenuTargetContext?

	/// Validates `menu`, then snapshots the items it left visible.
	///
	/// `update()` is what runs the validators, so it also settles the titles,
	/// the hidden flags and the submenus a validator attaches.
	static func validating(_ menu: NSMenu, context: MenuTargetContext? = nil) -> [MenuItemSnapshot] {
		if let context {
			return context.resolver.withContext(context.context) {
				snapshot(menu, context: context)
			}
		}
		return snapshot(menu, context: nil)
	}

	private static func snapshot(_ menu: NSMenu, context: MenuTargetContext?) -> [MenuItemSnapshot] {
		menu.update()

		return menu.items.compactMap { item in
			guard item.isHidden == false else { return nil }

			let content: Content = if item.isSeparatorItem {
				.separator
			} else if let submenu = item.submenu {
				.submenu(snapshot(submenu, context: context))
			} else {
				.command(action: item.action, target: item.target)
			}

			return MenuItemSnapshot(
				id: ObjectIdentifier(item),
				sender: item,
				command: item.command,
				title: item.title,
				isEnabled: item.isEnabled,
				isOn: item.state == .on,
				shortcut: shortcut(for: item),
				content: content,
				context: context
			)
		}
	}

	/// The item's key equivalent, as SwiftUI spells one. AppKit stores the
	/// character and the modifiers separately and a command with no shortcut
	/// stores an empty string.
	private static func shortcut(for item: NSMenuItem) -> KeyboardShortcut? {
		guard let character = item.keyEquivalent.first else { return nil }

		var modifiers: EventModifiers = []
		let mask = item.keyEquivalentModifierMask
		if mask.contains(.command) {
			modifiers.insert(.command)
		}
		if mask.contains(.shift) {
			modifiers.insert(.shift)
		}
		if mask.contains(.option) {
			modifiers.insert(.option)
		}
		if mask.contains(.control) {
			modifiers.insert(.control)
		}

		return KeyboardShortcut(KeyEquivalent(character), modifiers: modifiers)
	}

	@discardableResult
	func perform(prepareSelection: () -> Void) -> Bool {
		guard isEnabled, case let .command(action?, target) = content else { return false }

		/* Publishing the selection is the point of the click, not part of the
		 clicked-row context: only the command itself is answered for the row
		 the menu was opened on. */
		prepareSelection()

		guard let context else {
			return NSApp.sendAction(action, to: target, from: sender)
		}

		return context.resolver.withContext(context.context) {
			NSApp.sendAction(action, to: target, from: sender)
		}
	}
}

private struct MenuItemView: View {
	let entry: MenuItemSnapshot
	let prepareSelection: () -> Void

	var body: some View {
		switch entry.content {
		case .separator:
			Divider()
		case let .submenu(children):
			Menu {
				MenuContentView.submenu(children, prepareSelection)
			} label: {
				menuLabel
			}
			.disabled(entry.isEnabled == false)
			.modifier(KeyboardShortcutModifier(shortcut: entry.shortcut))
		case .command where entry.isOn:
			/* A ticked command is a state, and a toggle is how SwiftUI draws
			 one inside a menu. */
			Toggle(isOn: Binding(get: { true }, set: { _ in perform() })) {
				menuLabel
			}
			.disabled(entry.isEnabled == false)
			.modifier(KeyboardShortcutModifier(shortcut: entry.shortcut))
		case .command:
			Button(action: perform) {
				menuLabel
			}
			.disabled(entry.isEnabled == false)
			.modifier(KeyboardShortcutModifier(shortcut: entry.shortcut))
		}
	}

	private func perform() {
		entry.perform(prepareSelection: prepareSelection)
	}

	@ViewBuilder
	private var menuLabel: some View {
		if let symbolName = entry.command?.symbolName {
			Label(entry.title, systemImage: symbolName)
		} else {
			Text(entry.title)
		}
	}
}

/// `keyboardShortcut(_:)` takes a shortcut, not an optional one, and applying a
/// placeholder to a command that has none would claim a key the menu bar owns.
private struct KeyboardShortcutModifier: ViewModifier {
	let shortcut: KeyboardShortcut?

	func body(content: Content) -> some View {
		if let shortcut {
			content.keyboardShortcut(shortcut)
		} else {
			content
		}
	}
}
