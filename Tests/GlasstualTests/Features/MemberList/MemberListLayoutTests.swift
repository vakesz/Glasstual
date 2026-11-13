// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
@testable import Glasstual
import Testing

/// Saved initial widths must fit the native inspector's resize bounds.
@Suite("Member list width")
@MainActor
struct MemberListLayoutTests {
	@Test("Stored width validation agrees with the resize bounds",
	      arguments: [0.0, 159, 160, 200, 260, 261, Double.infinity, Double.nan])
	func settingAndLayoutShareBounds(width: Double) {
		let accepted = SettingsKeys.MainWindow.memberListWidth.accepts(width)
		#expect(accepted == (width.isFinite && CGFloat(width) >= MemberListLayout.minimumWidth
				&& CGFloat(width) <= MemberListLayout.maximumWidth))
	}
}
