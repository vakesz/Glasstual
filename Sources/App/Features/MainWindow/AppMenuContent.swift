/* *********************************************************************
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import AppKit
import SwiftUI

/// Renders the app's typed command menu graph as native SwiftUI menu content.
/// The `NSMenu` remains the macOS command boundary used by the menu bar and
/// responder chain; no AppKit view is hosted for contextual presentation.
struct AppMenuContent: View {
	let menu: NSMenu
	let prepareSelection: () -> Void

	var body: some View {
		ForEach(Array(menu.items.enumerated()), id: \.offset) { _, item in
			AppMenuItemContent(item: item, prepareSelection: prepareSelection)
		}
	}
}

private struct AppMenuItemContent: View {
	let item: NSMenuItem
	let prepareSelection: () -> Void

	var body: some View {
		if item.isSeparatorItem {
			Divider()
		} else if let submenu = item.submenu {
			Menu {
				AppMenuContent(menu: submenu, prepareSelection: prepareSelection)
			} label: {
				menuLabel
			}
			.disabled(isEnabled == false)
		} else {
			Button {
				prepareSelection()
				guard let action = item.action else { return }
				NSApp.sendAction(action, to: item.target, from: item)
			} label: {
				menuLabel
			}
			.disabled(isEnabled == false)
		}
	}

	@ViewBuilder
	private var menuLabel: some View {
		if let symbolName = item.command?.symbolName {
			Label(item.title, systemImage: symbolName)
		} else {
			Text(item.title)
		}
	}

	private var isEnabled: Bool {
		if let validator = item.target as? any NSMenuItemValidation {
			return validator.validateMenuItem(item)
		}
		return item.isEnabled
	}
}
