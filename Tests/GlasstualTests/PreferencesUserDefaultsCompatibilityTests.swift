/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import CocoaExtensions
import Foundation
@testable import Glasstual
import Testing

@MainActor
@Suite("Textual preference storage", .serialized)
struct PreferencesUserDefaultsCompatibilityTests {
	@Test("The compatibility numeric setter announces the key it changed")
	func compatibilityNumericSetterPostsPreferenceNotification() async {
		let defaults = TextualUserDefaults.container
		let key = "PreferencesUserDefaultsCompatibilityTests.\(UUID().uuidString)"
		let center = NotificationCenter.default
		defer { defaults.removeObject(forKey: key) }

		await confirmation("The preference change notification is posted") { changed in
			let token = center.addObserver(
				forName: .textualUserDefaultsDidChange,
				object: defaults,
				queue: nil
			) { notification in
				#expect(notification.userInfo?["changedKey"] as? String == key)
				changed()
			}
			defer { center.removeObserver(token) }

			defaults.setUnsignedInteger(42, forKey: key)
		}

		#expect(defaults.unsignedInteger(forKey: key) == 42)
	}

	@Test("The scalar setters still write the defaults keys the stored schema uses")
	func scalarSettersKeepTheirEstablishedDefaultsKeys() {
		let defaults = TextualUserDefaults.container
		let soundKey = "Notification Sound Is Muted"
		let portKey = "File Transfers -> File Transfer Port Range Start"
		let oldSound = defaults.object(forKey: soundKey)
		let oldPort = defaults.object(forKey: portKey)
		defer {
			defaults.set(oldSound, forKey: soundKey)
			defaults.set(oldPort, forKey: portKey)
		}

		Preferences.Notifications.soundIsMuted.value = true
		Preferences.FileTransfers.portRangeStart.value = 51234

		#expect(defaults.bool(forKey: soundKey))
		#expect(defaults.unsignedShort(forKey: portKey) == 51234)
	}

	@Test("A notification preference maps to the key the stored schema already holds")
	func notificationKeyMappingPreservesStoredSchema() {
		#expect(
			NotificationEvent.channelMessage.preferenceKeyName(for: .sound)
				== "NotificationType -> Public Message -> Sound"
		)
		#expect(
			NotificationEvent.fileTransferReceiveSuccessful.preferenceKeyName(for: .enabled)
				== "NotificationType -> Successful File Transfer (Receiving) -> Enabled"
		)
	}
}
