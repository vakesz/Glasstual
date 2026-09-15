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
		/* A validation message says what to enter; "properly formatted" told
		 the reader only that what they typed was wrong. */
		#expect(CommonValidationStrings.invalidNickname.hasPrefix("A nickname can contain "))
		#expect(CommonValidationStrings.maximumLength(390) == "Maximum length is 390 bytes.")
		#expect(CommonValidationStrings.maximumLength(1) == "Maximum length is 1 byte.")
		#expect(NotificationStrings.eventTypeTitle(for: .invite) == "Invitation")
		#expect(
			NotificationStrings.Membership.parted(nickname: "Alice", reason: "Leaving")
				== "Alice parted with reason: Leaving"
		)
		#expect(NotificationStrings.Membership.parted(nickname: "Alice", reason: nil) == "Alice parted")
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
