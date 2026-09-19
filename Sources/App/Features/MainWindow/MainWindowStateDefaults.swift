// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

struct MainWindowLayoutState: Equatable, Sendable {
	var isSidebarVisible: Bool
	var isMemberListVisible: Bool
}

/// The window's restored layout and zoom, read and written through the typed
/// key declarations that own those defaults.
struct MainWindowStateDefaults {
	private let defaults: UserDefaults

	/// Window restoration stays in the group container so every process-local
	/// app launch sees one state. It is deliberately excluded from settings
	/// import and export by the typed key declarations.
	init(defaults: UserDefaults = GlasstualUserDefaults.container) {
		self.defaults = defaults
	}

	func saveLayout(_ state: MainWindowLayoutState) {
		defaults[SettingsKeys.MainWindow.sidebarVisible] = state.isSidebarVisible
		defaults[SettingsKeys.MainWindow.memberListVisible] = state.isMemberListVisible
	}

	func loadLayout() -> MainWindowLayoutState {
		MainWindowLayoutState(
			isSidebarVisible: defaults[SettingsKeys.MainWindow.sidebarVisible],
			isMemberListVisible: defaults[SettingsKeys.MainWindow.memberListVisible]
		)
	}

	func saveTextSizeMultiplier(_ multiplier: Double) {
		defaults[SettingsKeys.MainWindow.textSizeMultiplier] = multiplier
	}

	/// The stored transcript zoom, or the declared default when what is stored
	/// is not a zoom the window is willing to apply.
	func loadTextSizeMultiplier() -> Double {
		let key = SettingsKeys.MainWindow.textSizeMultiplier
		guard let stored = defaults[stored: key],
		      key.accepts(stored)
		else {
			return key.defaultValue
		}

		return stored
	}

	func saveSelection(itemIdentifier: String?) {
		let key = SettingsKeys.MainWindow.sidebarSelection
		defaults[stored: key] = itemIdentifier.flatMap { $0.isEmpty ? nil : $0 }
	}

	func loadSelectionItemIdentifier() -> String? {
		let stored = defaults[SettingsKeys.MainWindow.sidebarSelection]
		return stored.isEmpty ? nil : stored
	}
}
