/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import AppKit
@testable import Glasstual
import XCTest

private final class RegisteredWindowSpy: NSWindow {
	private(set) var orderFrontCount = 0

	override func makeKeyAndOrderFront(_: Any?) {
		orderFrontCount += 1
	}
}

@MainActor
final class ApplicationInfrastructureMigrationTests: XCTestCase {
	func testObjectiveCRuntimeNamesRemainAvailable() {
		XCTAssertNotNil(NSClassFromString("TXApplication"))
		XCTAssertNotNil(NSClassFromString("TXAppearance"))
		XCTAssertEqual(NSStringFromClass(ApplicationController.self), "TXMasterController")
		XCTAssertNotNil(NSClassFromString("TXWindowController"))
	}

	func testApplicationResponderSelectorsRemainAvailable() {
		XCTAssertTrue(Application.responds(to: NSSelectorFromString("checkForOtherCopiesOfGlasstualRunning")))
		XCTAssertTrue(Application.instancesRespond(to: NSSelectorFromString("performedCustomKeyboardEvent:")))
		XCTAssertTrue(Application.instancesRespond(to: NSSelectorFromString("sendCustomKeyboardEvent:toObject:")))
	}

	func testWindowControllerSelectorsRemainAvailable() {
		let selectors = [
			"addWindowToWindowList:",
			"addWindowToWindowList:inRelationTo:",
			"addWindowToWindowList:withDescription:",
			"removeWindowFromWindowList:",
			"removeWindowFromWindowList:inRelationTo:",
			"windowFromWindowList:",
			"windowsFromWindowList:",
			"maybeBringWindowForward:",
			"popMainWindowSheetIfExists",
		]

		for selector in selectors {
			XCTAssertTrue(WindowController.instancesRespond(to: NSSelectorFromString(selector)), selector)
		}
	}

	func testWindowControllerStoresAndRemovesWindowsByIdentity() {
		let registry = WindowController()
		let controller = WindowBase()
		controller.window = RegisteredWindowSpy()

		registry.addWindow(toWindowList: controller, withDescription: "custom-window")

		XCTAssertTrue(registry.window(fromWindowList: "custom-window") as? WindowBase === controller)
		registry.removeWindow(fromWindowList: controller)
		XCTAssertNil(registry.window(fromWindowList: "custom-window"))
	}

	func testWindowControllerBringsForwardTypedWindowWithoutKVC() {
		let registry = WindowController()
		let controller = WindowBase()
		let window = RegisteredWindowSpy()
		controller.window = window
		registry.addWindow(toWindowList: controller, withDescription: "typed-window")

		XCTAssertTrue(registry.maybeBringWindowForward("typed-window"))
		XCTAssertEqual(window.orderFrontCount, 1)
	}

	func testTerminatedWindowControllerRejectsNewRegistrations() {
		let registry = WindowController()
		let controller = WindowBase()
		controller.window = RegisteredWindowSpy()
		registry.addWindow(toWindowList: controller, withDescription: "window")

		registry.prepareForApplicationTermination()
		registry.addWindow(toWindowList: controller, withDescription: "window")

		XCTAssertNil(registry.window(fromWindowList: "window"))
	}

	func testAppearanceContractRemainsStable() {
		XCTAssertTrue(Appearance.instancesRespond(to: NSSelectorFromString("updateAppearance")))
		XCTAssertEqual(
			Notification.Name.applicationAppearanceChanged.rawValue,
			"TXApplicationAppearanceChangedNotification"
		)
		XCTAssertEqual(
			Notification.Name.systemAppearanceChanged.rawValue,
			"TXSystemAppearanceChangedNotification"
		)
	}
}
