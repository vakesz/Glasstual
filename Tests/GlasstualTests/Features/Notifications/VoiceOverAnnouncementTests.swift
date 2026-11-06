// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
@testable import Glasstual
import Testing

@Suite("VoiceOver announcements")
struct VoiceOverAnnouncementTests {
	@Test("An announcement carries its text at high priority")
	func announcementIsHighPriority() {
		let userInfo = VoiceOverAnnouncement.userInfo(for: "Disconnected from Libera")

		#expect(userInfo[.announcement] as? String == "Disconnected from Libera")
		#expect(userInfo[.priority] as? Int == NSAccessibilityPriorityLevel.high.rawValue)
	}

	@Test("Announcements are off until the person asks for them")
	func announcementsDefaultToOff() {
		#expect(SettingsKeys.Notifications.announceToVoiceOver.defaultValue == false)
		#expect(SettingsKeys.Notifications.all.contains { $0.name == SettingsKeys.Notifications.announceToVoiceOver.name })
	}
}
