// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit

/// What an accessibility announcement carries. Highlights and disconnects
/// interrupt what VoiceOver is saying, so they ask for high priority.
enum VoiceOverAnnouncement {
	static func userInfo(for message: String) -> [NSAccessibility.NotificationUserInfoKey: Any] {
		[
			.announcement: message,
			.priority: NSAccessibilityPriorityLevel.high.rawValue,
		]
	}
}
