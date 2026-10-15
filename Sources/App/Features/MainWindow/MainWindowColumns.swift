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
	var isSidebarVisible = true {
		didSet { window?.updateMinimumContentSize() }
	}

	/// True when the selected channel has a member list.
	private(set) var isMemberListAvailable = false {
		didSet { window?.updateMinimumContentSize() }
	}

	/// Visibility combines selection availability with the user's preference.
	var isMemberListVisible: Bool {
		isMemberListAvailable && userPrefersMemberList
	}

	/// Persists independently of availability so selecting a server preserves the preference.
	private(set) var userPrefersMemberList = true {
		didSet { window?.updateMinimumContentSize() }
	}

	/// The widths the columns last came to rest at, or open at. A closed
	/// column keeps its width for when it opens again.
	@ObservationIgnored private(set) var sidebarWidth = CGFloat(SettingsKeys.MainWindow.sidebarWidth.value)
	@ObservationIgnored private(set) var memberListWidth = CGFloat(SettingsKeys.MainWindow.memberListWidth.value)

	var transcript: TranscriptView?
	/// The transcript host hides its AppKit view while the loading overlay is visible.
	var isConversationObscured = false

	@ObservationIgnored weak var window: MainWindow?
	@ObservationIgnored private let theme: ThemeStore

	init(theme: ThemeStore = AppServices.theme) {
		self.theme = theme
	}

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

	/// Notes the sidebar's width while it is open.
	func recordSidebarWidth(_ width: CGFloat) {
		guard isSidebarVisible, SettingsKeys.MainWindow.sidebarWidth.accepts(Double(width)) else { return }
		sidebarWidth = width
		window?.updateMinimumContentSize()
	}

	/// Notes the member list's width while it is open.
	func recordMemberListWidth(_ width: CGFloat) {
		guard isMemberListVisible, SettingsKeys.MainWindow.memberListWidth.accepts(Double(width)) else { return }
		memberListWidth = width
		window?.updateMinimumContentSize()
	}

	/// The narrowest content that holds the open columns.
	var minimumContentWidth: CGFloat {
		MainWindowConstants.minimumContentWidth(
			sidebar: isSidebarVisible ? sidebarWidth : nil,
			memberList: isMemberListVisible ? memberListWidth : nil
		)
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

	/// The theme's background for the published appearance and contrast.
	/// Reading it observes `ThemeStore`, so the background redraws in place.
	var conversationBackground: Color {
		Color(nsColor: theme.backgroundColor)
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
