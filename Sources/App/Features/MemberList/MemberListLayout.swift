// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CoreGraphics

/// What the member list draws that nothing else does. The spacings and the row
/// metrics it shares with the rest of the window are `UISpacing` and
/// `UIListMetrics`; only the avatar and the profile popover are its own.
nonisolated enum MemberListLayout {
	/// The native inspector's initial width and resize bounds.
	static let minimumWidth: CGFloat = .init(SettingsKeys.MainWindow.memberListWidthRange.lowerBound)
	static let idealWidth: CGFloat = .init(SettingsKeys.MainWindow.memberListWidth.defaultValue)
	static let maximumWidth: CGFloat = .init(SettingsKeys.MainWindow.memberListWidthRange.upperBound)
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
