// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation
@testable import Glasstual
import Testing

@MainActor
@Suite("Settings storage", .serialized)
struct SettingsStorageTests {
	@Test("A scalar write announces the key it changed")
	func scalarWritePostsPreferenceNotification() async {
		let defaults = GlasstualUserDefaults.container
		let key = "Tests -> Preference Storage -> \(UUID().uuidString)"
		let center = NotificationCenter.default
		defer { defaults.removeObject(forKey: key) }

		await confirmation("The preference change notification is posted") { changed in
			let token = center.addObserver(
				forName: .userDefaultsDidChange,
				object: defaults,
				queue: nil
			) { notification in
				#expect(notification.userInfo?[SettingsChangeNotification.changedKeyUserInfoKey] as? String == key)
				changed()
			}
			defer { center.removeObserver(token) }

			defaults.set(42, forKey: key)
		}

		#expect(defaults.integer(forKey: key) == 42)
	}

	@Test("A typed write reaches the store under the declared name")
	func typedWritesReachTheirDeclaredKeys() {
		let defaults = GlasstualUserDefaults.container
		let soundKey = SettingsKeys.Notifications.soundIsMuted.name
		let portKey = SettingsKeys.FileTransfers.portRangeStart.name
		let oldSound = defaults.object(forKey: soundKey)
		let oldPort = defaults.object(forKey: portKey)
		defer {
			defaults.set(oldSound, forKey: soundKey)
			defaults.set(oldPort, forKey: portKey)
		}

		SettingsKeys.Notifications.soundIsMuted.value = true
		SettingsKeys.FileTransfers.portRangeStart.value = 51234

		#expect(defaults.bool(forKey: soundKey))
		#expect(defaults.integer(forKey: portKey) == 51234)
	}
}
