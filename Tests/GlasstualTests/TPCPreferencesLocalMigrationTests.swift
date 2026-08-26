/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

@testable import Glasstual
import ObjectiveC.runtime
import XCTest

final class TPCPreferencesLocalMigrationTests: XCTestCase {
	func testScalarSettersKeepTheirEstablishedDefaultsKeys() {
		let defaults = TPCPreferencesUserDefaults.shared()
		let soundKey = "Notification Sound Is Muted"
		let oldSound = defaults.object(forKey: soundKey)
		let oldPort = defaults.object(forKey: "File Transfers -> File Transfer Port Range Start")
		defer {
			defaults.set(oldSound, forKey: soundKey)
			defaults.set(oldPort, forKey: "File Transfers -> File Transfer Port Range Start")
		}

		TPCPreferences.setSoundIsMuted(true)
		TPCPreferences.setFileTransferPortRangeStart(51234)

		XCTAssertTrue(defaults.bool(forKey: soundKey))
		XCTAssertEqual(
			defaults.unsignedShort(forKey: "File Transfers -> File Transfer Port Range Start"),
			51234
		)
	}

	func testNotificationKeyMappingPreservesStoredSchema() {
		XCTAssertEqual(
			TPCPreferences.key(forEvent: .channelMessage, category: "Sound"),
			"NotificationType -> Public Message -> Sound"
		)
		XCTAssertEqual(
			TPCPreferences.key(forEvent: .fileTransferReceiveSuccessful, category: "Enabled"),
			"NotificationType -> Successful File Transfer (Receiving) -> Enabled"
		)
	}

	func testObjectiveCPreferenceSelectorsRemainAvailable() throws {
		let metaClass = try XCTUnwrap(object_getClass(TPCPreferences.self))
		let selectors = [
			"defaultNickname",
			"setLogToDisk:",
			"setThemeNameWithExistenceCheck:",
			"setSound:forEvent:",
			"setNotificationEnabled:forEvent:",
			"cleanUpHighlightKeywords",
			"initPreferences",
			"setTextFieldSmartLinks:",
		]

		for selectorName in selectors {
			XCTAssertTrue(
				class_respondsToSelector(metaClass, NSSelectorFromString(selectorName)),
				"Missing Objective-C class selector \(selectorName)"
			)
		}
	}
}
