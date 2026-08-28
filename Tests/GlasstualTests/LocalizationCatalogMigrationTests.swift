/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import Foundation
@testable import Glasstual
import XCTest

@MainActor
final class LocalizationCatalogMigrationTests: XCTestCase {
	func testTypedBoundariesResolveMigratedCatalogValues() {
		XCTAssertEqual(AccessibilityStrings.userListEntry(for: "Alice"), "User Alice in User List")
		XCTAssertEqual(AccessibilityStrings.mainWindow, "Main Window")
		XCTAssertEqual(CommonValidationStrings.invalidNickname, "Please enter a properly formatted nickname.")
		XCTAssertEqual(CommonValidationStrings.maximumLength(390), "Maximum length is 390 characters.")
		XCTAssertEqual(NotificationStrings.eventTypeTitle(for: .invite), "Channel Invitation")
		XCTAssertEqual(
			NotificationStrings.deliveredTitle(for: .highlight, subject: "#textual"),
			"Highlight: #textual"
		)
		XCTAssertEqual(
			NotificationStrings.Membership.parted(
				nickname: "Alice",
				channelName: "#textual",
				reason: "Leaving"
			),
			"Alice parted #textual with reason: Leaving"
		)
		XCTAssertEqual(
			NotificationStrings.FileTransfer.description(
				for: .fileTransferReceiveSuccessful,
				filename: "archive.zip",
				byteCount: 1024
			),
			"archive.zip (1 kB)"
		)
		XCTAssertEqual(NotificationSoundStrings.defaultSound, "Default Sound")
		XCTAssertEqual(NotificationSoundStrings.noSound, "No Sound")
	}
}
