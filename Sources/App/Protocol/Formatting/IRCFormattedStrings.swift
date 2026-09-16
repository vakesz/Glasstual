/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 *********************************************************************** */

// AppKit: rendering IRC formatting builds attributed strings out of NSColor
// and NSFont.
import AppKit
import Foundation

/// Applying and removing IRC formatting on a line of text.
///
/// Only what a control-code scan can answer from the string itself lives here.
/// Rendering reads a preference and builds `NSFont`/`NSColor` attributes, so it
/// belongs to the main actor and sits in the extension below.
nonisolated extension NSString { // nonisolated: pure
	var stringByAppendingIRCFormattingStop: String {
		(self as String) + String(utf16CodeUnits: [UniChar(TextFormatterControlCharacter.terminator)], count: 1)
	}

	var stripIRCEffects: String {
		TextFormatting.removingControlCodes(from: self as String)
	}
}

/// Rendering a line of IRC formatting into an attributed string.
extension NSString {
	/// Main-actor: it reads a preference the main actor owns and it renders
	/// with `NSFont`/`NSColor`, which is what every caller hands it anyway.
	func attributedString(
		withIRCFormatting preferredFont: NSFont,
		preferredFontColor: NSColor?,
		honorFormattingPreference formattingPreference: Bool
	) -> NSAttributedString? {
		if formattingPreference, Preferences.Messages.removeAllFormatting.value {
			return NSAttributedString(string: stripIRCEffects)
		}

		let attributes = TranscriptRendererConfiguration(
			preferredFont: preferredFont,
			preferredFontColor: preferredFontColor
		)

		return TranscriptRenderer.renderBody(asAttributedString: self as String, withAttributes: attributes)
	}

	func attributedString(
		withIRCFormatting preferredFont: NSFont,
		preferredFontColor: NSColor?
	) -> NSAttributedString? {
		attributedString(
			withIRCFormatting: preferredFont,
			preferredFontColor: preferredFontColor,
			honorFormattingPreference: false
		)
	}
}
