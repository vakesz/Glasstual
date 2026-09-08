/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import AppKit

/** Measurements TextKit 2 gives for a font, taken through a throwaway
 layout: the same numbers the views lay their text out with, without an
 `NSLayoutManager` -- whose answers are TextKit 1's, and which nothing here
 may hold, because a text view that is handed one leaves TextKit 2 for good. */
nonisolated enum TextLineMetrics { // nonisolated: value
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
