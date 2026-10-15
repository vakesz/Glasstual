// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit

/// The main window's own layout numbers: the widths its columns are built
/// from, the sizes it restores to, and the two strokes its input capsule
/// draws. A column's own metrics belong to that column -- the member list's
/// are ``MemberListLayout`` -- and what is here is what the window itself has
/// to leave room for.
nonisolated enum MainWindowConstants {
	/// The sidebar's initial width and resize bounds, shared with the stored
	/// width so a restored value always fits the column.
	static let sidebarMinimumWidth: CGFloat = .init(SettingsKeys.MainWindow.sidebarWidthRange.lowerBound)
	static let sidebarIdealWidth: CGFloat = .init(SettingsKeys.MainWindow.sidebarWidth.defaultValue)
	static let sidebarMaximumWidth: CGFloat = .init(SettingsKeys.MainWindow.sidebarWidthRange.upperBound)
	static let conversationMinimumWidth: CGFloat = 360
	static let minimumSplitViewSlack: CGFloat = 60
	/// The member list's own metrics belong to the member list; its narrowest
	/// width is the one the window has to leave room for.
	static let minimumContentSize = NSSize(
		width: sidebarIdealWidth + conversationMinimumWidth + MemberListLayout.minimumWidth
			+ minimumSplitViewSlack,
		height: 500
	)
	/** The narrowest content that holds columns of these widths, `nil` for
	 a closed column.

	 The detail column runs under the sidebar and keeps the sidebar's width
	 as its inset. SwiftUI lays it out no narrower than that inset, so the
	 conversation beside the sidebar is never narrower than the sidebar. */
	static func minimumContentWidth(sidebar: CGFloat?, memberList: CGFloat?) -> CGFloat {
		max(minimumContentSize.width, columnsWidth(sidebar: sidebar ?? 0) + (memberList ?? 0))
	}

	/// The sidebar and the conversation beside it.
	private static func columnsWidth(sidebar: CGFloat) -> CGFloat {
		sidebar + max(sidebar, conversationMinimumWidth)
	}

	/** The widest the sidebar may be in content `width` points wide, leaving
	 the member list, when it is open, room for its narrowest width. */
	static func sidebarMaximumWidth(inContentWidth width: CGFloat, memberListOpen: Bool) -> CGFloat {
		let room = width - (memberListOpen ? MemberListLayout.minimumWidth : 0)
		// `columnsWidth` grows twice as fast once the sidebar passes the conversation's minimum.
		let widest = room >= 2 * conversationMinimumWidth ? room / 2 : room - conversationMinimumWidth
		return min(max(widest.rounded(.down), sidebarMinimumWidth), sidebarMaximumWidth)
	}

	/** The widest the member list may be in content `width` points wide
	 beside a sidebar `sidebar` points wide, `nil` when it is closed. */
	static func memberListMaximumWidth(inContentWidth width: CGFloat, sidebar: CGFloat?) -> CGFloat {
		let widest = width - columnsWidth(sidebar: sidebar ?? 0)
		return min(max(widest.rounded(.down), MemberListLayout.minimumWidth), MemberListLayout.maximumWidth)
	}

	static let minimumRestoredVisibleSize = NSSize(width: 80, height: 40)
	/// The size Reset Window gives back, before ``minimumContentSize`` is
	/// applied.
	static let defaultWindowSize = NSSize(width: 800, height: 474)
	static let sidebarFooterHeight: CGFloat = 32

	/// The footer icons' hit target: the smallest square that still reads as a
	/// control at the sidebar's foot.
	static let footerIconSize: CGFloat = 22
	/// The stroke the input capsule draws while it holds the keyboard.
	static let focusRingWidth: CGFloat = 2
	/// The same stroke where the system asks for increased contrast.
	static let focusRingWidthIncreasedContrast: CGFloat = 3
}
