/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import CocoaExtensions
@testable import Glasstual
import XCTest

@MainActor
final class TPCPreferencesLocalMigrationTests: XCTestCase {
	func testCompatibilityNumericSetterPostsPreferenceNotification() {
		let defaults = TextualUserDefaults.shared()
		let key = "TPCPreferencesLocalMigrationTests.\(UUID().uuidString)"
		let notificationExpectation = expectation(description: "Preference change notification")
		let center = NotificationCenter.default
		let token = center.addObserver(
			forName: .textualUserDefaultsDidChange,
			object: defaults,
			queue: nil
		) { notification in
			XCTAssertEqual(notification.userInfo?["changedKey"] as? String, key)
			notificationExpectation.fulfill()
		}
		defer {
			center.removeObserver(token)
			defaults.removeObject(forKey: key)
		}

		defaults.setUnsignedInteger(42, forKey: key)

		wait(for: [notificationExpectation], timeout: 1)
		XCTAssertEqual(defaults.unsignedInteger(forKey: key), 42)
	}

	func testScalarSettersKeepTheirEstablishedDefaultsKeys() {
		let defaults = TextualUserDefaults.shared()
		let soundKey = "Notification Sound Is Muted"
		let oldSound = defaults.object(forKey: soundKey)
		let oldPort = defaults.object(forKey: "File Transfers -> File Transfer Port Range Start")
		defer {
			defaults.set(oldSound, forKey: soundKey)
			defaults.set(oldPort, forKey: "File Transfers -> File Transfer Port Range Start")
		}

		TextualPreferences.setSoundIsMuted(true)
		TextualPreferences.setFileTransferPortRangeStart(51234)

		XCTAssertTrue(defaults.bool(forKey: soundKey))
		XCTAssertEqual(
			defaults.unsignedShort(forKey: "File Transfers -> File Transfer Port Range Start"),
			51234
		)
	}

	func testNotificationKeyMappingPreservesStoredSchema() {
		XCTAssertEqual(
			TextualPreferences.key(for: .channelMessage, category: "Sound"),
			"NotificationType -> Public Message -> Sound"
		)
		XCTAssertEqual(
			TextualPreferences.key(for: .fileTransferReceiveSuccessful, category: "Enabled"),
			"NotificationType -> Successful File Transfer (Receiving) -> Enabled"
		)
	}
}
