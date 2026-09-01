/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import AppKit
@testable import Glasstual
import Testing

@MainActor
@Suite("Application infrastructure")
struct ApplicationInfrastructureTests {
	/** Custom key-down handling used to be looked up by selector and called
	 through a bit-cast IMP. It is a Swift protocol now, so the contract is that
	 the classes offered the event conform to it. */
	@Test("Every class offered a key-down event conforms to the responder protocol")
	func customKeyboardEventRespondersConformToTheProtocol() {
		#expect((Application.self as Any.Type) is any CustomKeyboardEventResponder.Type)
		#expect((MainWindow.self as Any.Type) is any CustomKeyboardEventResponder.Type)
		#expect((TextViewWithIRCFormatter.self as Any.Type) is any CustomKeyboardEventResponder.Type)
	}

	/// The names predate the Swift API and may still be observed by plugins, so
	/// their raw values remain an external compatibility contract.
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
