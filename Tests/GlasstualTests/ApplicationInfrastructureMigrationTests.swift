/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import AppKit
@testable import Glasstual
import Testing

private final class RegisteredWindowSpy: NSWindow {
	private(set) var orderFrontCount = 0

	override func makeKeyAndOrderFront(_: Any?) {
		orderFrontCount += 1
	}
}

@MainActor
@Suite("Application infrastructure")
struct ApplicationInfrastructureMigrationTests {
	/** Custom key-down handling used to be looked up by selector and called
	 through a bit-cast IMP. It is a Swift protocol now, so the contract is that
	 the classes offered the event conform to it. */
	@Test("Every class offered a key-down event conforms to the responder protocol")
	func customKeyboardEventRespondersConformToTheProtocol() {
		#expect((Application.self as Any.Type) is any CustomKeyboardEventResponder.Type)
		#expect((MainWindow.self as Any.Type) is any CustomKeyboardEventResponder.Type)
		#expect((TextViewWithIRCFormatter.self as Any.Type) is any CustomKeyboardEventResponder.Type)
	}

	@Test("A window is looked up by its description and removed by identity")
	func windowControllerStoresAndRemovesWindowsByIdentity() {
		let registry = WindowController()
		let controller = WindowBase()
		controller.window = RegisteredWindowSpy()

		registry.addWindow(toWindowList: controller, withDescription: "custom-window")

		#expect(registry.window(fromWindowList: "custom-window") as? WindowBase === controller)

		registry.removeWindow(fromWindowList: controller)

		#expect(registry.window(fromWindowList: "custom-window") == nil)
	}

	@Test("Bringing a registered window forward orders its typed window front")
	func windowControllerBringsForwardTypedWindowWithoutKVC() {
		let registry = WindowController()
		let controller = WindowBase()
		let window = RegisteredWindowSpy()
		controller.window = window
		registry.addWindow(toWindowList: controller, withDescription: "typed-window")

		#expect(registry.maybeBringWindowForward("typed-window"))
		#expect(window.orderFrontCount == 1)
	}

	@Test("A registry that has prepared for termination accepts no more windows")
	func terminatedWindowControllerRejectsNewRegistrations() {
		let registry = WindowController()
		let controller = WindowBase()
		controller.window = RegisteredWindowSpy()
		registry.addWindow(toWindowList: controller, withDescription: "window")

		registry.prepareForApplicationTermination()
		registry.addWindow(toWindowList: controller, withDescription: "window")

		#expect(registry.window(fromWindowList: "window") == nil)
	}

	/// Three call sites observe these by literal name rather than through the
	/// declared constants, so the raw values are part of the contract.
	@Test("The appearance notification names match the literals observers register")
	func appearanceNotificationNamesMatchTheirObservers() {
		#expect(
			Notification.Name.applicationAppearanceChanged.rawValue
				== "TXApplicationAppearanceChangedNotification"
		)
		#expect(
			Notification.Name.systemAppearanceChanged.rawValue
				== "TXSystemAppearanceChangedNotification"
		)
	}
}
