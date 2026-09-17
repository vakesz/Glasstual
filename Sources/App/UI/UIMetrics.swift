// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
import CoreGraphics

/** The window's spacing scale.

 Everything the app spaces by is one of these, so a value that drifted off the
 four-point grid shows up as a name that does not exist rather than as a number
 nobody questions. There used to be one of these per feature -- the main
 window's, the member list's, the sidebar's, the input bar's -- with the same
 four numbers under four sets of names, which is three chances for one of them
 to be edited on its own and the columns beside it to stop lining up. */
enum UISpacing {
	/// 4 pt. Between an icon and the label it belongs to.
	static let tight: CGFloat = 4
	/// 8 pt. Between neighbouring controls in a strip.
	static let regular: CGFloat = 8
	/// 12 pt. A strip's own side margin.
	static let wide: CGFloat = 12
	/// 16 pt. The gap the input capsule keeps from the column's sides, and the
	/// margin a popover keeps around its content.
	static let loose: CGFloat = 16
}

/// What a row in either sidebar is built from. The member list and the server
/// list are two lists of the same shape beside the same conversation, so a row
/// height or a glyph column that differed between them would read as a mistake.
enum UIListMetrics {
	/// The height every sidebar row settles at, badges and glyphs included.
	static let rowHeight: CGFloat = 28
	/// The column a leading or trailing status glyph is centred in, so that the
	/// labels beside them line up whether or not a row has one.
	static let glyphWidth: CGFloat = 16
}

/** Measurements TextKit 2 gives for a font, taken through a throwaway
 layout: the same numbers the views lay their text out with, without an
 `NSLayoutManager` -- whose answers are TextKit 1's, and which nothing here
 may hold, because a text view that is handed one leaves TextKit 2 for good. */
nonisolated enum TextLineMetrics {
	/// The height of one line set in `font`.
	static func lineHeight(for font: NSFont) -> CGFloat {
		let contentStorage = NSTextContentStorage()
		let layoutManager = NSTextLayoutManager()
		contentStorage.addTextLayoutManager(layoutManager)
		layoutManager.textContainer = NSTextContainer(size: NSSize(width: 10000, height: 10000))
		contentStorage.attributedString = NSAttributedString(string: "X", attributes: [.font: font])
		layoutManager.ensureLayout(for: layoutManager.documentRange)
		return layoutManager.usageBoundsForTextContainer.height
	}
}
