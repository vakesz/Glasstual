/* *********************************************************************
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import AppKit
import SwiftUI

/// Renders the app's typed command menu graph as native SwiftUI menu content.
/// The `NSMenu` remains the macOS command boundary used by the menu bar and
/// responder chain; no AppKit view is hosted for contextual presentation.
///
/// The menus handed here are the shared AppKit ones, whose validators express
/// availability through `isHidden` as often as through enablement. They are
/// therefore validated once, up front, and snapshotted — the body then only
/// reads that snapshot, so drawing the menu never mutates AppKit state.
struct AppMenuContent: View {
	private let entries: [AppMenuEntry]
	private let prepareSelection: () -> Void

	init(menu: NSMenu, prepareSelection: @escaping () -> Void) {
		entries = AppMenuEntry.validating(menu)
		self.prepareSelection = prepareSelection
	}

	private init(entries: [AppMenuEntry], prepareSelection: @escaping () -> Void) {
		self.entries = entries
		self.prepareSelection = prepareSelection
	}

	var body: some View {
		ForEach(entries) { entry in
			AppMenuItemContent(entry: entry, prepareSelection: prepareSelection)
		}
	}

	fileprivate static func submenu(_ entries: [AppMenuEntry], _ prepareSelection: @escaping () -> Void) -> Self {
		Self(entries: entries, prepareSelection: prepareSelection)
	}
}

/// One item AppKit left visible, with everything the SwiftUI menu draws or
/// sends read at validation time.
struct AppMenuEntry: Identifiable {
	enum Content {
		case separator
		case command(action: Selector?, target: AnyObject?)
		case submenu([AppMenuEntry])
	}

	/// The menu item's own identity: two items can share a command (the same
	/// action appears in the menu bar and in a context menu) and an index
	/// changes as soon as validation hides a neighbour.
	let id: ObjectIdentifier
	let item: NSMenuItem
	let title: String
	let symbolName: String?
	let isEnabled: Bool
	let content: Content

	/// Validates `menu`, then snapshots the items it left visible.
	///
	/// `update()` is what runs the validators, so it also settles the titles,
	/// the hidden flags and the submenus a validator attaches.
	static func validating(_ menu: NSMenu) -> [AppMenuEntry] {
		menu.update()

		return menu.items.compactMap { item in
			guard item.isHidden == false else { return nil }

			let content: Content = if item.isSeparatorItem {
				.separator
			} else if let submenu = item.submenu {
				.submenu(validating(submenu))
			} else {
				.command(action: item.action, target: item.target)
			}

			return AppMenuEntry(
				id: ObjectIdentifier(item),
				item: item,
				title: item.title,
				symbolName: item.command?.symbolName,
				isEnabled: item.isEnabled,
				content: content
			)
		}
	}
}

private struct AppMenuItemContent: View {
	let entry: AppMenuEntry
	let prepareSelection: () -> Void

	var body: some View {
		switch entry.content {
		case .separator:
			Divider()
		case let .submenu(children):
			Menu {
				AppMenuContent.submenu(children, prepareSelection)
			} label: {
				menuLabel
			}
			.disabled(entry.isEnabled == false)
		case let .command(action, target):
			Button {
				prepareSelection()
				guard let action else { return }
				NSApp.sendAction(action, to: target, from: entry.item)
			} label: {
				menuLabel
			}
			.disabled(entry.isEnabled == false)
		}
	}

	@ViewBuilder
	private var menuLabel: some View {
		if let symbolName = entry.symbolName {
			Label(entry.title, systemImage: symbolName)
		} else {
			Text(entry.title)
		}
	}
}
