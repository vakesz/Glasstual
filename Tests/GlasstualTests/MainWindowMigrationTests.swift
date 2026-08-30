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

	@Test("The layout and the selection come back out of the store as they went in")
	func mainWindowStateStoreRoundTripsTypedState() throws {
		let suiteName = "MainWindowMigrationTests.\(UUID().uuidString)"
		let defaults = try #require(UserDefaults(suiteName: suiteName))
		defer { defaults.removePersistentDomain(forName: suiteName) }
		let store = MainWindowStateStore(defaults: defaults)
		let layout = MainWindowLayoutState(isServerListVisible: false, isMemberListVisible: true)

		store.saveLayout(layout)
		store.saveSelection(itemIdentifiers: ["server", "channel"])

		#expect(store.loadLayout() == layout)
		#expect(store.loadSelectionItemIdentifiers() == ["server", "channel"])
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
