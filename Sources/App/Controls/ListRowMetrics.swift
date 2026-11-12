// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit

/** The text and glyph sizes of a list row, from the row size the table is
 drawn at.

 System Settings › Appearance › Sidebar icon size sets the effective row size
 of every table whose style is `.default`. A source list's own cells take 11,
 13 or 15 pt text and glyphs of the same point size at small, medium and large;
 the sidebar draws its custom cells to the same scale, and the member list
 beside it follows the same setting. */
struct ListRowMetrics: Equatable {
	/// The three sizes System Settings offers.
	enum Size: Equatable {
		case small
		case medium
		case large
	}

	/// The point size of a row's title and of the symbols beside it.
	let textPointSize: CGFloat
	/// The point size of a second line, a count or a secondary glyph.
	let secondaryPointSize: CGFloat
	/// The column a leading glyph is centred in, so titles line up whether or
	/// not a row has one.
	let glyphWidth: CGFloat
	/// The diameter of a person's avatar in a one-line row.
	let avatarSize: CGFloat

	init(_ size: Size) {
		switch size {
		case .small:
			textPointSize = 11
			secondaryPointSize = 10
			glyphWidth = 17
			avatarSize = 20
		case .medium:
			textPointSize = 13
			secondaryPointSize = 11
			glyphWidth = 19
			avatarSize = 24
		case .large:
			textPointSize = 15
			secondaryPointSize = 13
			glyphWidth = 21
			avatarSize = 28
		}
	}

	/// A one-line row that holds an avatar: the avatar and the system's 4 pt
	/// margin above and below it.
	var avatarRowHeight: CGFloat {
		avatarSize + 2 * UISpacing.tight
	}

	/// A row that sets a title over a second line: both lines, the point
	/// between them and a margin above and below, never shorter than a
	/// one-line row of the same size.
	func twoLineRowHeight(oneLineRowHeight: CGFloat) -> CGFloat {
		let title = TextLineMetrics.lineHeight(for: .systemFont(ofSize: textPointSize))
		let subtitle = TextLineMetrics.lineHeight(for: .systemFont(ofSize: secondaryPointSize))
		return max(oneLineRowHeight, (title + 1 + subtitle + 2 * UISpacing.snug).rounded(.up))
	}

	/// A section heading's row: one line of caption text and the margins of a
	/// group row.
	static var sectionRowHeight: CGFloat {
		(TextLineMetrics.lineHeight(for: .preferredFont(forTextStyle: .caption1)) + 2 * UISpacing.tight).rounded(.up)
	}
}
