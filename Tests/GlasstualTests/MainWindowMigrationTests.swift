/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import Foundation
@testable import Glasstual
import Testing

@MainActor
@Suite("Main window state")
struct MainWindowMigrationTests {
	@Test("A window that has never been laid out shows both lists")
	func mainWindowStateStoreUsesVisibleDefaults() throws {
		let suiteName = "MainWindowMigrationTests.\(UUID().uuidString)"
		let defaults = try #require(UserDefaults(suiteName: suiteName))
		defer { defaults.removePersistentDomain(forName: suiteName) }

		#expect(
			MainWindowStateStore(defaults: defaults).loadLayout()
				== MainWindowLayoutState(isServerListVisible: true, isMemberListVisible: true)
		)
	}

	@Test("The layout and singular selection come back out of the store as they went in")
	func mainWindowStateStoreRoundTripsTypedState() throws {
		let suiteName = "MainWindowMigrationTests.\(UUID().uuidString)"
		let defaults = try #require(UserDefaults(suiteName: suiteName))
		defer { defaults.removePersistentDomain(forName: suiteName) }
		let store = MainWindowStateStore(defaults: defaults)
		let layout = MainWindowLayoutState(isServerListVisible: false, isMemberListVisible: true)

		store.saveLayout(layout)
		store.saveSelection(itemIdentifier: "channel")

		#expect(store.loadLayout() == layout)
		#expect(store.loadSelectionItemIdentifier() == "channel")
	}

	@Test("A legacy selection array migrates to its last identifier")
	func mainWindowStateStoreMigratesLegacySelection() throws {
		let suiteName = "MainWindowMigrationTests.\(UUID().uuidString)"
		let defaults = try #require(UserDefaults(suiteName: suiteName))
		defer { defaults.removePersistentDomain(forName: suiteName) }
		let key = "Window -> Main Window -> Server List Selection"
		defaults.set(["server", "channel"], forKey: key)

		let store = MainWindowStateStore(defaults: defaults)

		#expect(store.loadSelectionItemIdentifier() == "channel")
		#expect(defaults.string(forKey: key) == "channel")
	}

	@Test("The member list only expands for a channel on a session that has logged in")
	func memberListVisibilityRequiresAnActiveServerSession() {
		#expect(
			MainWindowMemberListVisibilityPolicy.shouldExpand(
				isChannel: true,
				isLoggedIn: false,
				isHiddenByUser: false
			) == false
		)
		#expect(
			MainWindowMemberListVisibilityPolicy.shouldExpand(
				isChannel: true,
				isLoggedIn: true,
				isHiddenByUser: false
			)
		)
		#expect(
			MainWindowMemberListVisibilityPolicy.shouldExpand(
				isChannel: false,
				isLoggedIn: true,
				isHiddenByUser: false
			) == false
		)
		#expect(
			MainWindowMemberListVisibilityPolicy.shouldExpand(
				isChannel: true,
				isLoggedIn: true,
				isHiddenByUser: true
			) == false
		)
	}
}
