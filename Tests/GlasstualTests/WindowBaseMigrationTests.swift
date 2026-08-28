/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import AppKit
@testable import Glasstual
import Testing

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

@MainActor
@Suite("Window base")
struct WindowBaseMigrationTests {
	@Test("Showing orders the window front, and both ok and cancel close it")
	func windowBaseForwardsWindowLifecycleActions() {
		let window = WindowBaseSpy()
		let controller = WindowBase()
		controller.window = window

		controller.show()
		controller.ok(nil)
		controller.cancel(nil)

		#expect(window.orderFrontCount == 1)
		#expect(window.closeCount == 2)
	}
}
