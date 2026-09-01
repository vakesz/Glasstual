/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import CoreGraphics
import Foundation
@testable import Glasstual
import Testing

@MainActor
@Suite("Main window state")
struct MainWindowPersistenceTests {
	@Test("A window that has never been laid out shows both lists")
	func mainWindowStateStoreUsesVisibleDefaults() throws {
		let suiteName = "MainWindowPersistenceTests.\(UUID().uuidString)"
		let defaults = try #require(UserDefaults(suiteName: suiteName))
		defer { defaults.removePersistentDomain(forName: suiteName) }

		#expect(
			MainWindowStateStore(defaults: defaults).loadLayout()
				== MainWindowLayoutState(isServerListVisible: true, isMemberListVisible: true)
		)
	}

	@Test("The layout and singular selection come back out of the store as they went in")
	func mainWindowStateStoreRoundTripsTypedState() throws {
		let suiteName = "MainWindowPersistenceTests.\(UUID().uuidString)"
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
		let suiteName = "MainWindowPersistenceTests.\(UUID().uuidString)"
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
		#expect(MainWindowMemberListVisibilityPolicy.isAvailable(isChannel: true, isLoggedIn: true))
		#expect(MainWindowMemberListVisibilityPolicy.isAvailable(isChannel: true, isLoggedIn: false) == false)
		#expect(MainWindowMemberListVisibilityPolicy.isAvailable(isChannel: false, isLoggedIn: true) == false)

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

	@Test("Corrupt and off-screen frames are repaired without moving valid windows")
	func mainWindowFrameRestorationRepairsOnlyInvalidGeometry() {
		let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
		let minimumSize = CGSize(width: 480, height: 360)
		let minimumVisibleSize = CGSize(width: 80, height: 40)
		let validFrame = CGRect(x: 120, y: 160, width: 800, height: 474)

		#expect(
			MainWindowFrameRestorationPolicy.repairedFrame(
				validFrame,
				minimumSize: minimumSize,
				minimumVisibleSize: minimumVisibleSize,
				visibleScreenFrames: [screen]
			) == validFrame
		)

		let repairedTinyFrame = MainWindowFrameRestorationPolicy.repairedFrame(
			CGRect(x: 292, y: 478, width: 1, height: 84),
			minimumSize: minimumSize,
			minimumVisibleSize: minimumVisibleSize,
			visibleScreenFrames: [screen]
		)
		#expect(repairedTinyFrame.size == minimumSize)
		#expect(screen.contains(repairedTinyFrame))

		let repairedOffscreenFrame = MainWindowFrameRestorationPolicy.repairedFrame(
			CGRect(x: 3000, y: 2000, width: 800, height: 474),
			minimumSize: minimumSize,
			minimumVisibleSize: minimumVisibleSize,
			visibleScreenFrames: [screen, CGRect(x: 1440, y: 0, width: 1024, height: 768)]
		)
		#expect(screen.contains(repairedOffscreenFrame))
		#expect(repairedOffscreenFrame.midX == screen.midX)
		#expect(repairedOffscreenFrame.midY == screen.midY)
	}
}
