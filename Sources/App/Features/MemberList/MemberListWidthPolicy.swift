// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CoreGraphics

/// The widths the member list is allowed to settle on. A drag, an arrow key
/// and the double-click reset all land here, so none of them can put a width
/// into the setting that the column cannot lay out.
nonisolated enum MemberListWidthPolicy {
	static func clamped(_ candidate: CGFloat) -> CGFloat {
		min(
			MemberListLayout.maximumWidth,
			max(MemberListLayout.minimumWidth, candidate)
		)
	}
}
