// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
@testable import Glasstual
import Testing

@MainActor
@Suite("Onboarding appearance preview", .serialized)
struct OnboardingAppearancePreviewTests {
	@MainActor private final class SystemPreferenceFixture {
		var mode = AppearanceMode.light
	}

	@Test("Explicit Light and Dark drafts override the system snapshot")
	func explicitDraftPreview() {
		var draft = OnboardingAppearance()
		draft.preferredAppearance = .light
		#expect(draft.previewMode(systemMode: .dark) == .light)
		draft.preferredAppearance = .dark
		#expect(draft.previewMode(systemMode: .light) == .dark)
	}

	@Test("A forced app appearance does not change the System preview or saved preference")
	func systemPreviewIgnoresAppOverride() {
		let previousAppearance = NSApp.appearance
		defer { NSApp.appearance = previousAppearance }
		let savedPreference = SettingsKeys.Appearance.preferredAppearance.storedValue
		let forced = NSAppearance(named: .aqua)
		NSApp.appearance = forced
		let snapshot = SystemAppearanceSnapshot(readMode: { .dark }, notificationCenter: NotificationCenter())

		#expect(OnboardingAppearance().previewMode(systemMode: snapshot.mode) == .dark)
		#expect(NSApp.appearance === forced)
		#expect(SettingsKeys.Appearance.preferredAppearance.storedValue == savedPreference)
	}

	@Test("The external preference decoder treats absent and unknown styles as Light")
	func externalPreferenceDecoding() {
		#expect(SystemAppearancePreference.decode(interfaceStyle: "Dark") == .dark)
		#expect(SystemAppearancePreference.decode(interfaceStyle: nil) == .light)
		#expect(SystemAppearancePreference.decode(interfaceStyle: "Light") == .light)
		#expect(SystemAppearancePreference.decode(interfaceStyle: "FutureStyle") == .light)
	}

	@Test("Defaults changes and returning to the app refresh the owned system snapshot",
	      arguments: [UserDefaults.didChangeNotification, NSApplication.didBecomeActiveNotification])
	func refreshesSnapshot(notification: Notification.Name) async {
		let center = NotificationCenter()
		let preference = SystemPreferenceFixture()
		let snapshot = SystemAppearanceSnapshot(readMode: { preference.mode }, notificationCenter: center)
		#expect(snapshot.mode == .light)
		preference.mode = .dark
		center.post(name: notification, object: nil)
		for _ in 0 ..< 100 where snapshot.mode != .dark {
			await Task.yield()
		}
		#expect(snapshot.mode == .dark)
	}
}
