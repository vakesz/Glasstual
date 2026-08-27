/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

@testable import Glasstual
import ObjectiveC.runtime
import XCTest

@MainActor
final class MainWindowMigrationTests: XCTestCase {
	func testMainWindowStateStoreUsesVisibleDefaults() throws {
		let suiteName = "MainWindowMigrationTests.\(UUID().uuidString)"
		let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
		defer { defaults.removePersistentDomain(forName: suiteName) }

		XCTAssertEqual(
			MainWindowStateStore(defaults: defaults).loadLayout(),
			MainWindowLayoutState(isServerListVisible: true, isMemberListVisible: true)
		)
	}

	func testMainWindowStateStoreRoundTripsTypedState() throws {
		let suiteName = "MainWindowMigrationTests.\(UUID().uuidString)"
		let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
		defer { defaults.removePersistentDomain(forName: suiteName) }
		let store = MainWindowStateStore(defaults: defaults)
		let layout = MainWindowLayoutState(isServerListVisible: false, isMemberListVisible: true)

		store.saveLayout(layout)
		store.saveSelection(itemIdentifiers: ["server", "channel"])

		XCTAssertEqual(store.loadLayout(), layout)
		XCTAssertEqual(store.loadSelectionItemIdentifiers(), ["server", "channel"])
	}

	func testMemberListVisibilityRequiresAnActiveServerSession() {
		XCTAssertFalse(
			MainWindowMemberListVisibilityPolicy.shouldExpand(
				isChannel: true,
				isLoggedIn: false,
				isHiddenByUser: false
			)
		)
		XCTAssertTrue(
			MainWindowMemberListVisibilityPolicy.shouldExpand(
				isChannel: true,
				isLoggedIn: true,
				isHiddenByUser: false
			)
		)
		XCTAssertFalse(
			MainWindowMemberListVisibilityPolicy.shouldExpand(
				isChannel: false,
				isLoggedIn: true,
				isHiddenByUser: false
			)
		)
		XCTAssertFalse(
			MainWindowMemberListVisibilityPolicy.shouldExpand(
				isChannel: true,
				isLoggedIn: true,
				isHiddenByUser: true
			)
		)
	}

	func testObjectiveCRuntimeNameRemainsStableForNibLoading() {
		XCTAssertEqual(NSStringFromClass(MainWindow.self), "TVCMainWindow")
	}

	func testResponderAndControllerSelectorsRemainAvailable() {
		let selectors = [
			"prepareForApplicationTermination",
			"inputHistoryManager",
			"channelView",
			"reloadingTheme",
			"select:",
			"selectPreviousItem",
			"deselect:",
			"deselectGroup:",
			"navigateServerEntries:withNavigationType:",
			"navigateChannelEntries:withNavigationType:",
			"navigateToNextEntry:",
			"selectNextServer:",
			"selectNextChannel:",
			"selectNextWindow:",
			"selectPreviousServer:",
			"selectPreviousChannel:",
			"selectPreviousWindow:",
			"changeTextSize:",
			"markAllAsRead",
			"markAllAsReadInGroup:",
			"reloadTheme",
			"clearContentsOfClient:",
			"clearContentsOfChannel:",
			"clearAllViews",
			"textEntered",
			"expandServerList",
			"collapseServerList",
			"toggleServerListVisibility",
			"expandMemberList",
			"collapseMemberList",
			"toggleMemberListVisibility",
			"locationOfMouseInWindow",
			"locationOfMouse:",
			"updateTitle",
			"updateTitleFor:",
			"reloadTree",
			"reloadTreeItem:",
			"reloadTreeGroup:",
			"adjustSelection",
			"updateDrawingForUserInUserList:",
		]

		for selectorName in selectors {
			XCTAssertNotNil(
				class_getInstanceMethod(MainWindow.self, NSSelectorFromString(selectorName)),
				"Missing Objective-C selector \(selectorName)"
			)
		}
	}

	func testNotificationsRetainHistoricNames() {
		XCTAssertEqual(
			Notification.Name.mainWindowAppearanceChanged.rawValue,
			"TVCMainWindowAppearanceChangedNotification"
		)
		XCTAssertEqual(Notification.Name.mainWindowRedrawSubviews.rawValue, "TVCMainWindowRedrawSubviewsNotification")
		XCTAssertEqual(Notification.Name.mainWindowWillReloadTheme.rawValue, "TVCMainWindowWillReloadThemeNotification")
		XCTAssertEqual(Notification.Name.mainWindowDidReloadTheme.rawValue, "TVCMainWindowDidReloadThemeNotification")
		XCTAssertEqual(
			Notification.Name.mainWindowSelectionChanged.rawValue,
			"TVCMainWindowSelectionChangedNotification"
		)
	}
}
