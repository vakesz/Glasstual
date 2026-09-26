// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
@testable import Glasstual
import Testing

/// The drag, the arrow keys and the double-click reset all settle on a width
/// through one place, so none of them can store a width the column cannot lay
/// out.
@Suite("Member list width")
@MainActor
struct MemberListLayoutTests {
	@Test("Stored width validation agrees with the resize bounds",
	      arguments: [0.0, 159, 160, 200, 260, 261, Double.infinity, Double.nan])
	func settingAndLayoutShareBounds(width: Double) {
		let accepted = SettingsKeys.MainWindow.memberListWidth.accepts(width)
		#expect(accepted == (width.isFinite && width >= 160 && width <= 260))
		if accepted {
			#expect(MemberListLayout.clampedWidth(CGFloat(width)) == CGFloat(width))
		}
	}

	@Test("A width inside the range is kept")
	func widthsInRangeAreKept() {
		#expect(MemberListLayout.clampedWidth(MemberListLayout.idealWidth)
			== MemberListLayout.idealWidth)
	}

	@Test("A width outside the range is pulled back to the nearest edge")
	func widthsOutsideRangeAreClamped() {
		#expect(MemberListLayout.clampedWidth(0) == MemberListLayout.minimumWidth)
		#expect(MemberListLayout.clampedWidth(10000) == MemberListLayout.maximumWidth)
		#expect(MemberListLayout.clampedWidth(-40) == MemberListLayout.minimumWidth)
	}

	/// One press of an arrow key moves the edge by a step and stays in range at
	/// either end.
	@Test("Stepping from an edge does not leave the range")
	func steppingStaysInRange() {
		let step = MemberListLayout.keyboardResizeStep
		let atMinimum = MemberListLayout.minimumWidth

		#expect(MemberListLayout.clampedWidth(atMinimum - step) == atMinimum)
		#expect(MemberListLayout.clampedWidth(atMinimum + step) == atMinimum + step)
	}
}
