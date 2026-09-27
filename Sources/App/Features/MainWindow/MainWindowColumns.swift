// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
import Observation
import SwiftUI

/// Owns column visibility, the displayed transcript and its background.
/// Sheets and toolbar state belong to `MainWindowSheetModel` and `MainWindowChrome`.
@MainActor
@Observable
final class MainWindowColumnModel {
	var isSidebarVisible = true
	/// True when the selected channel has a member list.
	private(set) var isMemberListAvailable = false
	/// Visibility combines selection availability with the user's preference.
	var isMemberListVisible: Bool {
		isMemberListAvailable && userPrefersMemberList
	}

	/// Persists independently of availability so selecting a server preserves the preference.
	private(set) var userPrefersMemberList = true
	var transcript: TranscriptView?
	/// The transcript host hides its AppKit view while the loading overlay is visible.
	var isConversationObscured = false
	var appearanceRevision = 0

	@ObservationIgnored weak var window: MainWindow?

	func attach(to window: MainWindow) {
		precondition(self.window == nil || self.window === window)
		self.window = window
	}

	/// A joined channel makes the member-list column available.
	func applyMemberListAvailability(_ isAvailable: Bool) {
		if !isAvailable {
			window?.prepareToHideMemberList()
		}
		isMemberListAvailable = isAvailable
	}

	/// Shared by the menu and toolbar commands.
	func toggleMemberList() {
		setMemberListVisible(!userPrefersMemberList)
	}

	/// Native inspector changes apply only while the selection has a member list.
	func setMemberListVisible(_ isVisible: Bool) {
		guard isMemberListAvailable else { return }
		if !isVisible {
			window?.prepareToHideMemberList()
		}
		userPrefersMemberList = isVisible
	}

	/// Restores saved column visibility preferences.
	func restoreColumns(_ state: MainWindowLayoutState) {
		isSidebarVisible = state.isSidebarVisible
		userPrefersMemberList = state.isMemberListVisible
	}

	var columnState: MainWindowLayoutState {
		MainWindowLayoutState(
			isSidebarVisible: isSidebarVisible,
			isMemberListVisible: userPrefersMemberList
		)
	}

	/// Reads the appearance revision for system appearance and contrast changes;
	/// edits to the theme itself are observed through `ThemeStore`.
	var conversationBackground: Color {
		_ = appearanceRevision
		return Color(nsColor: AppServices.theme.backgroundColor)
	}
}

/// Column commands share the system's Reduce Motion setting.
@MainActor
enum MainWindowColumnAnimation {
	static func run(_ change: () -> Void) {
		withAnimation(ReduceMotion.animation(.default)) {
			change()
		}
	}
}
