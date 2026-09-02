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
