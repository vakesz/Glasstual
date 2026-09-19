// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

// AppKit: rendering IRC formatting builds attributed strings out of NSColor
// and NSFont.
import AppKit
import Foundation

/// The font and colour a line of IRC formatting is drawn against where the text
/// carries none of its own.
struct TranscriptFormattingAttributes {
	var preferredFont: NSFont?
	var preferredFontColor: NSColor?
}

/** Turns IRC control codes into the attributed string an `NSTextView` draws.

 The transcript itself does not come through here: it renders a semantic
 ``TranscriptBody`` that holds no AppKit objects at all. This is the other path
 — the input field, the topic bar, the member list, the channel list and the
 highlight list, which show a line of IRC text the way the transcript would and
 need `NSFont`/`NSColor` attributes plus the `TextFormatterAttributeName` keys
 the formatting menu reads back out of a selection.

 Main-actor: building fonts and colours is presentation, and every caller is
 already there. */
enum TranscriptFormattedText {
	static func render(_ body: String, with attributes: TranscriptFormattingAttributes) -> NSAttributedString {
		let parsed = FormattingParser.parse(body)
		let result = NSMutableAttributedString(attributedString: parsed)
		parsed.enumerateAttributes(in: NSRange(location: 0, length: parsed.length)) { runAttributes, range, _ in
			result.addAttributes(appKitAttributes(from: runAttributes, with: attributes), range: range)
		}
		return result
	}

	private static func appKitAttributes(
		from runAttributes: [NSAttributedString.Key: Any],
		with attributes: TranscriptFormattingAttributes
	) -> [NSAttributedString.Key: Any] {
		var result: [NSAttributedString.Key: Any] = [:]
		let defaultColor = attributes.preferredFontColor
		var font = attributes.preferredFont
		if runAttributes[RendererFormatting.monospace] != nil, let current = font {
			font = NSFontManager.shared.convert(current, toFamily: "Menlo")
			result[NSAttributedString.Key(TextFormatterAttributeName.monospaceAttributeName.rawValue)] = true
		}
		if runAttributes[RendererFormatting.bold] != nil, let current = font {
			font = NSFontManager.shared.convert(current, toHaveTrait: .boldFontMask)
			result[NSAttributedString.Key(TextFormatterAttributeName.boldAttributeName.rawValue)] = true
		}
		if runAttributes[RendererFormatting.italic] != nil, let current = font {
			font = NSFontManager.shared.convert(current, toHaveTrait: .italicFontMask)
			result[NSAttributedString.Key(TextFormatterAttributeName.italicAttributeName.rawValue)] = true
		}
		result[.font] = font
		if runAttributes[RendererFormatting.strikethrough] != nil {
			result[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
			result[NSAttributedString.Key(TextFormatterAttributeName.strikethroughAttributeName.rawValue)] = true
		}
		if runAttributes[RendererFormatting.underline] != nil {
			result[.underlineStyle] = NSUnderlineStyle.single.rawValue
			result[NSAttributedString.Key(TextFormatterAttributeName.underlineAttributeName.rawValue)] = true
		}
		if let foreground = runAttributes[RendererFormatting.foregroundColor] {
			result[.foregroundColor] = mapColor(foreground)
			result[NSAttributedString.Key(TextFormatterAttributeName.foregroundColorAttributeName.rawValue)] =
				foreground
		} else if let defaultColor {
			result[.foregroundColor] = defaultColor
		}
		if let background = runAttributes[RendererFormatting.backgroundColor] {
			result[.backgroundColor] = mapColor(background)
			result[NSAttributedString.Key(TextFormatterAttributeName.backgroundColorAttributeName.rawValue)] =
				background
		}
		return result.compactMapValues { $0 }
	}

	/// The colour a formatting run carries, whether it named a palette index or
	/// an `NSColor` of its own.
	nonisolated static func mapColor(_ color: Any) -> NSColor? { // nonisolated: pure
		if let color = color as? NSColor {
			return color
		}
		if let color = color as? NSNumber {
			return MircColorPalette.mapColorCode(color.uintValue)
		}
		return nil
	}
}

/** The bridge every view outside the transcript reaches for.

 The renderer is the transcript's, so the bridge to it lives here rather than in
 the protocol layer, which must not depend on how a line is presented. */
extension NSString {
	/// Main-actor: it reads a setting the main actor owns and it renders
	/// with `NSFont`/`NSColor`, which is what every caller hands it anyway.
	func attributedString(
		withIRCFormatting preferredFont: NSFont,
		preferredFontColor: NSColor?,
		honorFormattingSetting formattingSetting: Bool
	) -> NSAttributedString? {
		if formattingSetting, SettingsKeys.Messages.removeAllFormatting.value {
			return NSAttributedString(string: stripIRCEffects)
		}

		return TranscriptFormattedText.render(
			self as String,
			with: TranscriptFormattingAttributes(
				preferredFont: preferredFont,
				preferredFontColor: preferredFontColor
			)
		)
	}

	func attributedString(
		withIRCFormatting preferredFont: NSFont,
		preferredFontColor: NSColor?
	) -> NSAttributedString? {
		attributedString(
			withIRCFormatting: preferredFont,
			preferredFontColor: preferredFontColor,
			honorFormattingSetting: false
		)
	}
}
