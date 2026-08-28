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
@testable import Glasstual
import Testing

@Suite("Main window state store suite")
@MainActor
struct MainWindowStateStoreSuiteTests {
	private static let keys = [
		"Window -> Main Window -> Server List is Visible",
		"Window -> Main Window -> Member List is Visible",
		"Window -> Main Window -> Server List Selection",
	]

	/// Preference export/import reads these keys out of the group container, so
	/// the window state has to be written there rather than to `.standard`.
	@Test("The store writes to the shared container suite by default")
	func defaultSuiteIsTheSharedContainer() {
		let container = TextualUserDefaults.shared()
		for key in Self.keys {
			container.removeObject(forKey: key)
			UserDefaults.standard.removeObject(forKey: key)
		}
		defer {
			for key in Self.keys {
				container.removeObject(forKey: key)
			}
		}

		let store = MainWindowStateStore()
		store.saveLayout(MainWindowLayoutState(isServerListVisible: false, isMemberListVisible: false))
		store.saveSelection(itemIdentifiers: ["an-identifier"])

		#expect(container.object(forKey: Self.keys[0]) != nil)
		#expect(container.object(forKey: Self.keys[1]) != nil)
		#expect(container.stringArray(forKey: Self.keys[2]) == ["an-identifier"])

		let reloaded = store.loadLayout()
		#expect(reloaded.isServerListVisible == false)
		#expect(reloaded.isMemberListVisible == false)
		#expect(store.loadSelectionItemIdentifiers() == ["an-identifier"])
	}

	@Test("All three keys are listed in the exportable master list")
	func keysAreExportable() throws {
		let url = try #require(Bundle.main.url(
			forResource: "PreferenceKeyMasterList",
			withExtension: "plist",
			subdirectory: "Preferences"
		))
		let plist = try PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil)
		let listed = try #require(plist as? [String: Any])
		for key in Self.keys {
			#expect(listed[key] != nil)
		}
	}
}
