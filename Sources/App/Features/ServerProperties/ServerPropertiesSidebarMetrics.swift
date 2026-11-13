// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
import SwiftUI

/** How wide the pane list is.

 The list is always shown and never resized, as System Settings' is, so its
 width is the widest pane name's: a name that does not fit has no way to be
 read. The limits keep a short language from a narrow strip and a long one
 from taking the panes' room. */
enum ServerPropertiesSidebarMetrics {
	static let minimumWidth: CGFloat = 190
	static let maximumWidth: CGFloat = 300

	/// What a row puts around its name: the list's inset and the row's own
	/// padding on both sides, the symbol column and the gap after it.
	static let rowChrome: CGFloat = 80

	/// The column width that shows a name `titleWidth` points wide in full.
	static func width(forTitleWidth titleWidth: CGFloat) -> CGFloat {
		min(maximumWidth, max(minimumWidth, (titleWidth + rowChrome).rounded(.up)))
	}

	/// The width of the widest of `titles` as a sidebar row draws its name.
	/// The selected row is drawn heavier, so every name is measured that way.
	static func widestTitleWidth(_ titles: [String], rowSize: SidebarRowSize) -> CGFloat {
		let font = NSFont.systemFont(ofSize: pointSize(for: rowSize), weight: .semibold)
		return titles
			.map { NSAttributedString(string: $0, attributes: [.font: font]).size().width }
			.max() ?? 0
	}

	/// The text size the system draws a sidebar row at, for the row size the
	/// reader chose in System Settings.
	private static func pointSize(for rowSize: SidebarRowSize) -> CGFloat {
		switch rowSize {
		case .small: 11
		case .large: 15
		default: 13
		}
	}
}
