/* *********************************************************************
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import Foundation

/// The text the transcript itself shows: what a reader hears in place of a
/// picture or a reaction, and what an image offers on a right click.
nonisolated enum TranscriptViewStrings { // nonisolated: value
	static var copyImage: String {
		String(localized: .TranscriptView.copyImage)
	}

	static var saveImage: String {
		String(localized: .TranscriptView.saveImage)
	}

	static var openImageLink: String {
		String(localized: .TranscriptView.openImageLink)
	}

	static func imageAccessibility(source: String) -> String {
		String(localized: .TranscriptView.imageAccessibility(source))
	}

	static func reactionAccessibility(emoji: String, count: Int) -> String {
		String(localized: .TranscriptView.reactionAccessibility(emoji, count))
	}
}
