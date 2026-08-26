/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import AppKit
@testable import Glasstual
import XCTest

private final class WindowBaseSpy: NSWindow {
	private(set) var orderFrontCount = 0
	private(set) var closeCount = 0

	override func makeKeyAndOrderFront(_: Any?) {
		orderFrontCount += 1
	}

	override func close() {
		closeCount += 1
	}
}

final class WindowBaseMigrationTests: XCTestCase {
	func testWindowBaseForwardsWindowLifecycleActions() {
		let window = WindowBaseSpy()
		let controller = WindowBase()
		controller.window = window

		controller.show()
		controller.ok(nil)
		controller.cancel(nil)

		XCTAssertEqual(window.orderFrontCount, 1)
		XCTAssertEqual(window.closeCount, 2)
	}
}
