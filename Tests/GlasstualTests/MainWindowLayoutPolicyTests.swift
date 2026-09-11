/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

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

/** Every submenu shares the coordinator as its delegate, so AppKit sends
 `menuWillOpen` and `menuDidClose` for each of them as the pointer moves in and
 out. Treating those as session boundaries re-read the window's selection half
 way through a menu, and a command chosen from a submenu of a right-clicked row
 then acted on the selected row instead of the clicked one. */
@Suite("Menu session boundaries")
@MainActor
struct MenuLifecyclePolicyRootMenuTests {
	@Test("Only a menu with no supermenu opens and closes a session")
	func onlyRootMenusBoundASession() {
		let root = NSMenu(title: "Root")
		let submenu = NSMenu(title: "Submenu")
		let item = NSMenuItem(title: "More", action: nil, keyEquivalent: "")
		item.submenu = submenu
		root.addItem(item)

		#expect(MenuLifecyclePolicy.isRootMenu(supermenu: root.supermenu))
		#expect(MenuLifecyclePolicy.isRootMenu(supermenu: submenu.supermenu) == false)
	}

	@Test("The selection is reset only when the menu performed nothing")
	func selectionResetsOnlyWithoutAnAction() {
		#expect(MenuLifecyclePolicy.shouldResetSelectionAfterMenuCloses(performedAction: false))
		#expect(MenuLifecyclePolicy.shouldResetSelectionAfterMenuCloses(performedAction: true) == false)
	}
}

/// A switch names what the next press does, not the state it is in.
@Suite("Main window toggle titles")
@MainActor
struct MainWindowToggleTitleTests {
	@Test("The member list title follows the pane's state")
	func memberListTitleFollowsState() {
		let shown = MainWindowStrings.Menu.memberList(isVisible: true)
		let hidden = MainWindowStrings.Menu.memberList(isVisible: false)

		#expect(shown != hidden)
		#expect(shown.isEmpty == false)
		#expect(hidden.isEmpty == false)
	}

	@Test("The notification title follows the mute switch")
	func notificationTitleFollowsState() {
		let muted = MainWindowStrings.Menu.notifications(areDisabled: true)
		let unmuted = MainWindowStrings.Menu.notifications(areDisabled: false)

		#expect(muted != unmuted)
		#expect(muted.isEmpty == false)
		#expect(unmuted.isEmpty == false)
	}

	@Test("The resize handle carries a label and a keyboard hint")
	func resizeHandleIsDescribed() {
		#expect(MainWindowStrings.Toolbar.memberListWidth.isEmpty == false)
		#expect(MainWindowStrings.Toolbar.memberListWidthHint.isEmpty == false)
	}
}
