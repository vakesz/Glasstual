// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit

/** The edit half of the formatting menu: everything that reads or writes IRC
 formatting attributes in one message field.

 A value over the field rather than a collaborator that resolves one. The menu
 resolves the field once, through the window it belongs to, and hands it over --
 so an edit that touches several attributes (a spoiler carries two colours with
 it, the rainbow walk recolours every character) applies to the field the
 command started on, and the arithmetic below is exercisable against any
 ``FormattedTextView``. */
@MainActor
struct TextFormatterEditor {
	let field: FormattedTextView

	/// The palette entry a spoiler paints itself with, foreground and
	/// background alike, so the text reads as a solid block until it is
	/// selected.
	private static let spoilerColorCode = 14

	/// Whether the effect is set across the selection.
	func isSet(_ effect: TextFormatterEffectKind) -> Bool {
		field.attributedString().ircFormatterAttributeSet(
			inRange: effect,
			range: field.selectedRange()
		)
	}

	/// Turns a character effect on or off across the selection. A spoiler
	/// carries the two colours that hide the text with it.
	func setEffect(_ effect: TextFormatterEffectKind, enabled: Bool) {
		let range = field.selectedRange()
		let value: Any? = enabled ? true : nil

		guard effect == .spoiler else {
			apply(effect, value: value, in: range)
			return
		}

		let colorValue: Any? = enabled ? NSNumber(value: Self.spoilerColorCode) : nil
		if enabled {
			apply(.spoiler, value: value, in: range)
		}
		apply(.foregroundColor, value: colorValue, in: range)
		apply(.backgroundColor, value: colorValue, in: range)
		if enabled == false {
			apply(.spoiler, value: nil, in: range)
		}
	}

	/// Sets or clears one attribute over a range of the field's own text.
	func apply(_ effect: TextFormatterEffectKind, value: Any?, in limitRange: NSRange) {
		guard let copy = mutableString(at: limitRange) else {
			return
		}

		write(effect, value: value, in: NSRange(location: 0, length: copy.length), to: copy)
		replaceSelection(with: copy, in: limitRange)

		if value == nil, effect == .foregroundColor || effect == .spoiler {
			field.resetFontColor(in: limitRange)
		}

		if effect == .monospace, value == nil {
			field.resetFont(in: limitRange)
		}
	}

	/// Sets or clears one attribute over a range of a copy that is not in the
	/// field yet.
	private func write(
		_ effect: TextFormatterEffectKind,
		value: Any?,
		in limitRange: NSRange,
		to mutableString: NSMutableAttributedString
	) {
		if let value {
			mutableString.setIRCFormatterAttribute(effect, value: value, range: limitRange)
		} else {
			mutableString.removeIRCFormatterAttribute(effect, range: limitRange)
		}
	}

	/// Colours the selection one palette entry per character, cycling the seven
	/// codes a rainbow is made of.
	func applyRainbow(asForegroundColor: Bool) {
		let selectedTextRange = field.selectedRange()

		guard let copy = mutableString(at: selectedTextRange) else {
			return
		}

		copy.beginEditing()

		var rainbowArrayIndex = 0
		let colorCodes: [UInt] = [4, 7, 8, 3, 12, 2, 6]

		/* Coloured by composed character sequence, not by UTF-16 unit: a
		 surrogate pair or a combining sequence used to be split across two
		 colour codes, which broke the character.

		 Every index below belongs to this one bridged copy. Reading
		 `.string` again would hand back a different String, and an index
		 from one is not valid in another. */
		let text = copy.string

		text.enumerateSubstrings(
			in: text.startIndex ..< text.endIndex,
			options: .byComposedCharacterSequences
		) { [self] _, substringRange, _, _ in
			let currentColorCode = colorCodes[rainbowArrayIndex % colorCodes.count]
			let currentCharacterRange = NSRange(substringRange, in: text)

			write(
				asForegroundColor ? .foregroundColor : .backgroundColor,
				value: NSNumber(value: currentColorCode),
				in: currentCharacterRange,
				to: copy
			)

			rainbowArrayIndex += 1
		}

		copy.endEditing()
		replaceSelection(with: copy, in: selectedTextRange)
	}

	private func mutableString(at limitRange: NSRange) -> NSMutableAttributedString? {
		guard limitRange.location != NSNotFound, limitRange.length > 0 else {
			return nil
		}

		let substring = field.attributedString().attributedSubstring(from: limitRange)
		return substring.mutableCopy() as? NSMutableAttributedString
	}

	private func replaceSelection(
		with mutableString: NSMutableAttributedString,
		in limitRange: NSRange
	) {
		guard field.shouldChangeText(in: limitRange, replacementString: mutableString.string) else {
			return
		}

		field.textStorage?.replaceCharacters(in: limitRange, with: mutableString)
		field.didChangeText()
		field.setSelectedRange(limitRange)
	}
}
