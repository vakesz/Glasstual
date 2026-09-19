// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing

@Suite("Main window state defaults")
@MainActor
struct MainWindowStateDefaultsTests {
	private static let keys = [
		SettingsKeys.MainWindow.sidebarVisible.name,
		SettingsKeys.MainWindow.memberListVisible.name,
		SettingsKeys.MainWindow.sidebarSelection.name,
		SettingsKeys.MainWindow.textSizeMultiplier.name,
	]

	/// Preference export/import reads these keys out of the group container, so
	/// the window state has to be written there rather than to `.standard`.
	@Test("The store writes to the shared container suite by default")
	func defaultSuiteIsTheSharedContainer() {
		let container = GlasstualUserDefaults.container

		/* `.standard` is the developer's own domain — the test scheme redirects
		 the container and nothing else — so it is read to prove the write did
		 not land there, never written or cleared. */
		let standardBefore = Self.keys.map { UserDefaults.standard.object(forKey: $0) as? NSObject }

		for key in Self.keys {
			container.removeObject(forKey: key)
		}
		defer {
			for key in Self.keys {
				container.removeObject(forKey: key)
			}
		}

		let store = MainWindowStateDefaults()
		store.saveLayout(MainWindowLayoutState(isSidebarVisible: false, isMemberListVisible: false))
		store.saveSelection(itemIdentifier: "an-identifier")

		#expect(container.object(forKey: Self.keys[0]) != nil)
		#expect(container.object(forKey: Self.keys[1]) != nil)
		#expect(container.string(forKey: Self.keys[2]) == "an-identifier")

		let standardAfter = Self.keys.map { UserDefaults.standard.object(forKey: $0) as? NSObject }
		#expect(standardAfter == standardBefore, "the store wrote window state to the standard domain")

		let reloaded = store.loadLayout()
		#expect(reloaded.isSidebarVisible == false)
		#expect(reloaded.isMemberListVisible == false)
		#expect(store.loadSelectionItemIdentifier() == "an-identifier")
	}

	/** The zoom used to live only in the window object, so Increase Font Size
	 was undone by the next launch. A stored zoom outside the range the View
	 menu can reach is not applied: it would leave the transcript at a size no
	 command could walk back. */
	@Test("The transcript zoom survives a relaunch, and a stored zoom out of range does not")
	func textSizeMultiplierRoundTripsAndIsValidated() {
		let container = GlasstualUserDefaults.container
		let key = SettingsKeys.MainWindow.textSizeMultiplier.name
		container.removeObject(forKey: key)
		defer { container.removeObject(forKey: key) }

		let store = MainWindowStateDefaults()
		#expect(store.loadTextSizeMultiplier() == 1.0)

		store.saveTextSizeMultiplier(1.44)
		#expect(store.loadTextSizeMultiplier() == 1.44)

		store.saveTextSizeMultiplier(12)
		#expect(store.loadTextSizeMultiplier() == 1.0)

		store.saveTextSizeMultiplier(.nan)
		#expect(store.loadTextSizeMultiplier() == 1.0)
	}

	@Test("Window restoration keys are catalogued but excluded from settings export")
	func keysAreNotExported() {
		for key in Self.keys {
			#expect(SettingsKeys.isCatalogued(key))
			#expect(SettingsKeys.isExcludedFromExport(key))
		}
	}
}
