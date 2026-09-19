// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
import Observation
import SwiftUI

/** What the window's columns are showing.

 The two side columns, the transcript hosted between them, and the ground all
 three are painted on. Everything here is the window's own presentation; the
 sheets it raises are ``MainWindowSheetModel``'s and the toolbar and footer are
 ``MainWindowChrome``'s, so a subview observes only the part it draws. */
@MainActor
@Observable
final class MainWindowColumnModel {
	var isSidebarVisible = true
	/// Whether the selection has a member list at all: a joined channel has
	/// one, a server row and a one-to-one conversation do not.
	private(set) var isMemberListAvailable = false
	/// Whether the column is showing. Derived, never set from outside: the
	/// member list shows while the selection has one and the reader has not
	/// closed it.
	private(set) var isMemberListVisible = true
	/** Whether the reader wants the member list beside a channel that has one.

	 The pane's own visibility cannot carry this: it is false for every server
	 row too, so restoring it would have closed the list for good the first
	 time the reader left a server selected. This used to live on `MemberList`
	 as `isHiddenByUser`, a second store of the same fact that six call sites
	 kept in step with this one. */
	private(set) var userPrefersMemberList = true
	var transcript: TranscriptView?
	/// Whether the loading overlay covers the conversation. The transcript
	/// host hides its AppKit view while it does.
	var isConversationObscured = false
	var appearanceRevision = 0

	@ObservationIgnored weak var window: MainWindow?

	func attach(to window: MainWindow) {
		precondition(self.window == nil || self.window === window)
		self.window = window
	}

	/** Applies a selection to the member-list column.

	 One derivation, so the two facts cannot disagree: the column is available
	 beside a joined channel, and it is open while it is available and the
	 reader has not closed it. */
	func applyMemberListAvailability(_ isAvailable: Bool) {
		isMemberListAvailable = isAvailable
		isMemberListVisible = isAvailable && userPrefersMemberList
	}

	/** The reader's own switch, from either menu or the toolbar.

	 Nothing happens where there is no member list to show: both menus disable
	 the command there, and a "Show Member List" that quietly recorded "hide it"
	 is what the guard is for. */
	func toggleMemberList() {
		guard isMemberListAvailable else { return }
		userPrefersMemberList.toggle()
		isMemberListVisible = userPrefersMemberList
	}

	/// Restores what the reader last left the columns at.
	func restoreColumns(_ state: MainWindowLayoutState) {
		isSidebarVisible = state.isSidebarVisible
		userPrefersMemberList = state.isMemberListVisible
		isMemberListVisible = state.isMemberListVisible
	}

	var columnState: MainWindowLayoutState {
		MainWindowLayoutState(
			isSidebarVisible: isSidebarVisible,
			isMemberListVisible: userPrefersMemberList
		)
	}

	/** The ground the sidebar and the conversation both paint.

	 `appearanceRevision` is read so a theme change redraws it: the colour comes
	 from the theme controller, which is not observable on its own. */
	var conversationBackground: Color {
		_ = appearanceRevision
		return Color(nsColor: AppServices.theme.backgroundColor)
	}
}

/** The one animation a column change is shown with.

 A pane sweeping across the window is exactly the motion Reduce Motion asks an
 interface to drop, so the column simply appears instead. The state change is
 the same either way, which is why it is the view's to animate and the model
 only records it -- and why the toolbar button, the sidebar's overflow menu and
 the View menu all reach it here rather than each carrying their own wrapper. */
@MainActor
enum MainWindowColumnAnimation {
	static func run(_ change: () -> Void) {
		withAnimation(ReduceMotion.animation(.default)) {
			change()
		}
	}
}

extension View {
	/// Makes `change` -- a column appearing or disappearing -- the animation
	/// ``MainWindowColumnAnimation`` describes.
	func animatingColumnChange(_ change: () -> Void) {
		MainWindowColumnAnimation.run(change)
	}
}
