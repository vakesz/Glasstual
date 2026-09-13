/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
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
		Preferences.MainWindow.serverListVisible.name,
		Preferences.MainWindow.memberListVisible.name,
		Preferences.MainWindow.serverListSelection.name,
		Preferences.MainWindow.textSizeMultiplier.name,
	]

	/// Preference export/import reads these keys out of the group container, so
	/// the window state has to be written there rather than to `.standard`.
	@Test("The store writes to the shared container suite by default")
	func defaultSuiteIsTheSharedContainer() {
		let container = TextualUserDefaults.container

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

		let store = MainWindowStateStore()
		store.saveLayout(MainWindowLayoutState(isServerListVisible: false, isMemberListVisible: false))
		store.saveSelection(itemIdentifier: "an-identifier")

		#expect(container.object(forKey: Self.keys[0]) != nil)
		#expect(container.object(forKey: Self.keys[1]) != nil)
		#expect(container.string(forKey: Self.keys[2]) == "an-identifier")

		let standardAfter = Self.keys.map { UserDefaults.standard.object(forKey: $0) as? NSObject }
		#expect(standardAfter == standardBefore, "the store wrote window state to the standard domain")

		let reloaded = store.loadLayout()
		#expect(reloaded.isServerListVisible == false)
		#expect(reloaded.isMemberListVisible == false)
		#expect(store.loadSelectionItemIdentifier() == "an-identifier")
	}

	/** The zoom used to live only in the window object, so Increase Font Size
	 was undone by the next launch. A stored zoom outside the range the View
	 menu can reach is not applied: it would leave the transcript at a size no
	 command could walk back. */
	@Test("The transcript zoom survives a relaunch, and a stored zoom out of range does not")
	func textSizeMultiplierRoundTripsAndIsValidated() {
		let container = TextualUserDefaults.container
		let key = Preferences.MainWindow.textSizeMultiplier.name
		container.removeObject(forKey: key)
		defer { container.removeObject(forKey: key) }

		let store = MainWindowStateStore()
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
			#expect(Preferences.isCatalogued(key))
			#expect(Preferences.isExcludedFromExport(key))
		}
	}
}
