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
import GlasstualPluginKit

/// Applying and removing IRC formatting on a line of text.
public nonisolated extension NSString { // nonisolated: pure
	var stringByAppendingIRCFormattingStop: String {
		(self as String) + String(utf16CodeUnits: [UniChar(IRCTextFormatterControlCharacter.terminator)], count: 1)
	}

	/// Main-actor: it reads a preference the main actor owns and it renders
	/// with `NSFont`/`NSColor`, which is what every caller hands it anyway.
	@MainActor
	func attributedString(
		withIRCFormatting preferredFont: NSFont,
		preferredFontColor: NSColor?,
		honorFormattingPreference formattingPreference: Bool
	) -> NSAttributedString? {
		if formattingPreference, Preferences.Messages.removeAllFormatting.value {
			return NSAttributedString(string: stripIRCEffects)
		}

		var attributes = LogRendererConfiguration()

		attributes[.preferredFont] = preferredFont

		if let preferredFontColor {
			attributes[.preferredFontColor] = preferredFontColor
		}

		return LogRenderer.renderBody(asAttributedString: self as String, withAttributes: attributes)
	}

	@MainActor
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

	var stripIRCEffects: String {
		IRCFormatting.removingControlCodes(from: self as String)
	}
}
