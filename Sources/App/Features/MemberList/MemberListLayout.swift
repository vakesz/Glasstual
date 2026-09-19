// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CoreGraphics

/// What the member list draws that nothing else does. The spacings and the row
/// metrics it shares with the rest of the window are `UISpacing` and
/// `UIListMetrics`; only the avatar and the profile popover are its own.
nonisolated enum MemberListLayout {
	/// What the column may be dragged between, and where a reset puts it.
	static let minimumWidth: CGFloat = 160
	static let idealWidth: CGFloat = 200
	static let maximumWidth: CGFloat = 260
	/// The draggable width of the edge between conversation and member list.
	static let handleWidth: CGFloat = 7
	/// One press of an arrow key on the focused resize handle.
	static let keyboardResizeStep: CGFloat = 16
	static let avatarSize: CGFloat = 24
	static let profileAvatarSize: CGFloat = 64
	static let profileLabelWidth: CGFloat = 72
	static let profileMinimumWidth: CGFloat = 280
	static let profileIdealWidth: CGFloat = 340
	static let profileMaximumWidth: CGFloat = 420
	/// How many lines an address or a real name may wrap onto before it is cut.
	/// A hostmask is routinely longer than the popover is wide.
	static let profileValueLineLimit = 3
}
