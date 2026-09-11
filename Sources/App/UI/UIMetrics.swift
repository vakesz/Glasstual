/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

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
