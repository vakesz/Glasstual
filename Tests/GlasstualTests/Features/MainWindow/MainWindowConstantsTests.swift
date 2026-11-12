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

	/** The floor holds the conversation beside the narrowest sidebar; the
	 open columns raise the minimum from there, so a window showing only the
	 conversation can be made small. */
	@Test("The minimum floor holds the conversation beside the narrowest sidebar")
	func minimumContentSizeFitsNarrowestColumns() {
		#expect(MainWindowConstants.minimumContentSize.width
			>= MainWindowConstants.sidebarMinimumWidth + MainWindowConstants.conversationMinimumWidth)
		#expect(MainWindowConstants.minimumContentSize.width < MainWindowConstants.minimumContentWidth(
			sidebar: MainWindowConstants.sidebarIdealWidth,
			memberList: MemberListLayout.minimumWidth
		))
	}

	/// First-party windows open comfortably larger than their minimum, and
	/// never larger than the screen they open on.
	@Test("The default size is larger than the minimum and fits the screen", arguments: [
		(NSSize(width: 2560, height: 1400), NSSize(width: 1040, height: 680)),
		(NSSize(width: 900, height: 600), NSSize(width: 900, height: 600)),
		(NSSize(width: 500, height: 300), NSSize(width: 640, height: 450)),
	])
	func defaultSizeFitsTheScreen(visible: NSSize, expected: NSSize) {
		let size = MainWindowConstants.defaultWindowSize(
			minimumSize: NSSize(width: 640, height: 450),
			visibleSize: visible
		)
		#expect(size == expected)
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
		Columns(sidebar: 180, memberList: nil, minimumWidth: MainWindowConstants.minimumContentSize.width),
		Columns(sidebar: 220, memberList: 200, minimumWidth: 220 + MainWindowConstants.conversationMinimumWidth + 200),
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

	@Test("In a narrow window the stored maximum widths are cut down")
	func narrowestWindowClampsWideColumns() {
		let width: CGFloat = 800
		#expect(MainWindowConstants.sidebarMaximumWidth(inContentWidth: width, memberListOpen: true) == 280)
		#expect(MainWindowConstants.sidebarMaximumWidth(inContentWidth: width, memberListOpen: false) == 400)
		#expect(MainWindowConstants.memberListMaximumWidth(inContentWidth: width, sidebar: 220) == 220)
		#expect(MainWindowConstants.memberListMaximumWidth(inContentWidth: width, sidebar: 400) == MemberListLayout.minimumWidth)
		#expect(MainWindowConstants.memberListMaximumWidth(inContentWidth: 1300, sidebar: 400) == 500)
	}
}
