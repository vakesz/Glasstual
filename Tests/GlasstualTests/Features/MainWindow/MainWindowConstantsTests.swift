// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
@testable import Glasstual
import Testing

/// Saved sidebar widths must fit the split view's resize bounds.
@Suite("Main window sidebar width")
@MainActor
struct MainWindowConstantsTests {
	@Test("Stored width validation agrees with the resize bounds",
	      arguments: [0.0, 179, 180, 220, 400, 401, Double.infinity, Double.nan])
	func settingAndLayoutShareBounds(width: Double) {
		let accepted = SettingsKeys.MainWindow.sidebarWidth.accepts(width)
		#expect(accepted == (width.isFinite && CGFloat(width) >= MainWindowConstants.sidebarMinimumWidth
				&& CGFloat(width) <= MainWindowConstants.sidebarMaximumWidth))
	}

	/// The window has to leave room for the narrowest layout, not the widest.
	@Test("Minimum content size fits every column at its narrowest")
	func minimumContentSizeFitsNarrowestColumns() {
		#expect(MainWindowConstants.minimumContentSize.width
			>= MainWindowConstants.sidebarMinimumWidth
			+ MainWindowConstants.conversationMinimumWidth
			+ MemberListLayout.minimumWidth)
	}

	struct Columns: Sendable, CustomTestStringConvertible {
		let sidebar: CGFloat?
		let memberList: CGFloat?
		let minimumWidth: CGFloat

		var testDescription: String {
			"sidebar \(sidebar.map { "\($0)" } ?? "closed"), member list \(memberList.map { "\($0)" } ?? "closed")"
		}
	}

	/** SwiftUI keeps the conversation at least as wide as the sidebar beside
	 it, and the conversation needs its own minimum besides. */
	@Test("Open columns widen the window's minimum past its floor", arguments: [
		Columns(sidebar: nil, memberList: nil, minimumWidth: MainWindowConstants.minimumContentSize.width),
		Columns(sidebar: 220, memberList: 200, minimumWidth: MainWindowConstants.minimumContentSize.width),
		Columns(sidebar: 300, memberList: 320, minimumWidth: 300 + MainWindowConstants.conversationMinimumWidth + 320),
		Columns(sidebar: 400, memberList: 500, minimumWidth: 400 + 400 + 500),
		Columns(sidebar: nil, memberList: 500, minimumWidth: MainWindowConstants.conversationMinimumWidth + 500),
	])
	func minimumContentWidthHoldsOpenColumns(columns: Columns) {
		#expect(MainWindowConstants.minimumContentWidth(sidebar: columns.sidebar, memberList: columns.memberList)
			== columns.minimumWidth)
	}

	/** A column is never offered more than the window holds beside the
	 others, nor less than its own minimum, so stored widths from a wider
	 window cannot demand more than this one can give. */
	@Test("Columns are offered only what the window holds", arguments: [800.0, 960, 1080, 1300, 2000])
	func offeredWidthsFitTheWindow(width: CGFloat) {
		let sidebar = MainWindowConstants.sidebarMaximumWidth(inContentWidth: width, memberListOpen: true)
		let memberList = MainWindowConstants.memberListMaximumWidth(inContentWidth: width, sidebar: sidebar)
		#expect(sidebar >= MainWindowConstants.sidebarMinimumWidth)
		#expect(sidebar <= MainWindowConstants.sidebarMaximumWidth)
		#expect(memberList >= MemberListLayout.minimumWidth)
		#expect(memberList <= MemberListLayout.maximumWidth)
		#expect(MainWindowConstants.minimumContentWidth(sidebar: sidebar, memberList: MemberListLayout.minimumWidth) <= max(
			width,
			MainWindowConstants.minimumContentSize.width
		))
		#expect(MainWindowConstants.minimumContentWidth(sidebar: sidebar, memberList: memberList) <= max(
			width,
			MainWindowConstants.minimumContentSize.width
		))
	}

	@Test("At the narrowest window the stored maximum widths are cut down")
	func narrowestWindowClampsWideColumns() {
		let width = MainWindowConstants.minimumContentSize.width
		#expect(MainWindowConstants.sidebarMaximumWidth(inContentWidth: width, memberListOpen: true) == 280)
		#expect(MainWindowConstants.sidebarMaximumWidth(inContentWidth: width, memberListOpen: false) == 400)
		#expect(MainWindowConstants.memberListMaximumWidth(inContentWidth: width, sidebar: 220) == 220)
		#expect(MainWindowConstants.memberListMaximumWidth(inContentWidth: width, sidebar: 400) == MemberListLayout.minimumWidth)
		#expect(MainWindowConstants.memberListMaximumWidth(inContentWidth: 1300, sidebar: 400) == 500)
	}
}
