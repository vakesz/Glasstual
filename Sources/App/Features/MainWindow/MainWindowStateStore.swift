/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \\ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\\___/_/\\_\\__|\\__,_|\\__,_|_|
 *
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 *********************************************************************** */

import Foundation

struct MainWindowLayoutState: Equatable, Sendable {
	var isServerListVisible: Bool
	var isMemberListVisible: Bool
}

struct MainWindowStateStore {
	private enum Key: String {
		case serverListVisibility = "Window -> Main Window -> Server List is Visible"
		case memberListVisibility = "Window -> Main Window -> Member List is Visible"
		case serverListSelection = "Window -> Main Window -> Server List Selection"
	}

	private let defaults: UserDefaults

	// All three keys are in PreferenceKeyMasterList.plist and not excluded from
	// the container, so preference export/import reads them out of the group
	// suite: they have to be written there too.
	init(defaults: UserDefaults = TextualUserDefaults.shared()) {
		self.defaults = defaults
	}

	func saveLayout(_ state: MainWindowLayoutState) {
		defaults.set(state.isServerListVisible, forKey: Key.serverListVisibility.rawValue)
		defaults.set(state.isMemberListVisible, forKey: Key.memberListVisibility.rawValue)
	}

	func loadLayout() -> MainWindowLayoutState {
		MainWindowLayoutState(
			isServerListVisible: storedBoolean(for: .serverListVisibility) ?? true,
			isMemberListVisible: storedBoolean(for: .memberListVisibility) ?? true
		)
	}

	func saveSelection(itemIdentifiers: [String]) {
		defaults.set(itemIdentifiers, forKey: Key.serverListSelection.rawValue)
	}

	func loadSelectionItemIdentifiers() -> [String] {
		defaults.stringArray(forKey: Key.serverListSelection.rawValue) ?? []
	}

	private func storedBoolean(for key: Key) -> Bool? {
		(defaults.object(forKey: key.rawValue) as? NSNumber)?.boolValue
	}
}
