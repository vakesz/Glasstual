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
	static let sidebarMinimumWidth: CGFloat = 180
	static let sidebarIdealWidth: CGFloat = 220
	static let sidebarMaximumWidth: CGFloat = 280
	static let conversationMinimumWidth: CGFloat = 360
	static let minimumSplitViewSlack: CGFloat = 60
	/// The member list's own metrics belong to the member list; its narrowest
	/// width is the one the window has to leave room for.
	static let minimumContentSize = NSSize(
		width: sidebarIdealWidth + conversationMinimumWidth + MemberListLayout.minimumWidth
			+ minimumSplitViewSlack,
		height: 500
	)
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
