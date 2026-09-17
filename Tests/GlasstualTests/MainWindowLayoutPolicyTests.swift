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
struct MemberListWidthPolicyTests {
	@Test("A width inside the range is kept")
	func widthsInRangeAreKept() {
		#expect(MemberListWidthPolicy.clamped(MainWindowConstants.memberListIdealWidth)
			== MainWindowConstants.memberListIdealWidth)
	}

	@Test("A width outside the range is pulled back to the nearest edge")
	func widthsOutsideRangeAreClamped() {
		#expect(MemberListWidthPolicy.clamped(0) == MainWindowConstants.memberListMinimumWidth)
		#expect(MemberListWidthPolicy.clamped(10000) == MainWindowConstants.memberListMaximumWidth)
		#expect(MemberListWidthPolicy.clamped(-40) == MainWindowConstants.memberListMinimumWidth)
	}

	/// One press of an arrow key moves the edge by a step and stays in range at
	/// either end.
	@Test("Stepping from an edge does not leave the range")
	func steppingStaysInRange() {
		let step = MainWindowConstants.memberListKeyboardResizeStep
		let atMinimum = MainWindowConstants.memberListMinimumWidth

		#expect(MemberListWidthPolicy.clamped(atMinimum - step) == atMinimum)
		#expect(MemberListWidthPolicy.clamped(atMinimum + step) == atMinimum + step)
	}
}

/// A switch names what the next press does, not the state it is in.
@Suite("Main window toggle titles")
@MainActor
struct MainWindowToggleTitleTests {
	@Test("The member list title follows the pane's state")
	func memberListTitleFollowsState() {
		let shown = MenuCommand.memberListTitle(isVisible: true)
		let hidden = MenuCommand.memberListTitle(isVisible: false)

		#expect(shown != hidden)
		#expect(shown.isEmpty == false)
		#expect(hidden.isEmpty == false)
	}
}
