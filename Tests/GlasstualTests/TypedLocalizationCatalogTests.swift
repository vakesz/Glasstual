/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import Foundation
@testable import Glasstual
import Testing

@MainActor
@Suite("Localization catalog boundaries")
struct TypedLocalizationCatalogTests {
	@Test("Every typed boundary resolves the value the migrated catalog holds")
	func typedBoundariesResolveMigratedCatalogValues() {
		#expect(AccessibilityStrings.userListEntry(for: "Alice") == "User Alice in User List")
		#expect(AccessibilityStrings.mainWindow == "Main Window")
		#expect(CommonValidationStrings.invalidNickname == "Please enter a properly formatted nickname.")
		#expect(CommonValidationStrings.maximumLength(390) == "Maximum length is 390 characters.")
		#expect(NotificationStrings.eventTypeTitle(for: .invite) == "Channel Invitation")
		#expect(
			NotificationStrings.deliveredTitle(for: .highlight, subject: "#textual") == "Highlight: #textual"
		)
		#expect(
			NotificationStrings.Membership.parted(
				nickname: "Alice",
				channelName: "#textual",
				reason: "Leaving"
			) == "Alice parted #textual with reason: Leaving"
		)
		#expect(
			NotificationStrings.FileTransfer.description(
				for: .fileTransferReceiveSuccessful,
				filename: "archive.zip",
				byteCount: 1024
			) == "archive.zip (1 kB)"
		)
		#expect(NotificationSoundStrings.defaultSound == "Default Sound")
		#expect(NotificationSoundStrings.noSound == "No Sound")
	}
}
