/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 *********************************************************************** */

import AppKit
import CocoaExtensions

/** Editing an attributed string's IRC formatting.

 These are the mutations the formatting menu and the input field make to text a
 person is still typing, so they belong beside the text view rather than in the
 protocol layer: they reach for `NSFont` and `NSColor`, and the only mutable
 attributed string the protocol layer ever saw was this one. */
extension NSMutableAttributedString {
	private func addIRCFontTrait(
		_ trait: NSFontTraitMask,
		formatterAttribute: TextFormatterAttributeName,
		baseFont: NSFont?,
		range: NSRange
	) {
		guard let baseFont else {
			return
		}

		let font = if baseFont.hasTrait(trait) {
			baseFont
		} else {
			NSFontManager.shared.convert(baseFont, toHaveTrait: trait)
		}

		addAttribute(formatterKey(formatterAttribute), value: true, range: range)
		addAttribute(.font, value: font, range: range)
	}

	private func addIRCColor(
		_ value: Any?,
		formatterAttribute: TextFormatterAttributeName,
		appKitAttribute: NSAttributedString.Key,
		range: NSRange
	) {
		if let colorCode = (value as? NSNumber)?.intValue,
		   (0 ... TextFormatterColor.maximumPaletteIndex).contains(colorCode)
		{
			addAttribute(formatterKey(formatterAttribute), value: colorCode, range: range)
			addAttribute(appKitAttribute, value: TranscriptRenderer.mapColorCode(UInt(colorCode)), range: range)
		} else if let color = value as? NSColor {
			addAttribute(formatterKey(formatterAttribute), value: color, range: range)
			addAttribute(appKitAttribute, value: color, range: range)
		}
	}

	private func applyIRCFormatterAttribute(
		_ effect: TextFormatterEffectType,
		value: Any?,
		attributes: [NSAttributedString.Key: Any],
		range: NSRange
	) {
		let baseFont = attributes[.font] as? NSFont

		switch effect {
		case .none:
			break
		case .bold:
			addIRCFontTrait(
				.boldFontMask,
				formatterAttribute: .boldAttributeName,
				baseFont: baseFont,
				range: range
			)
		case .italic:
			addIRCFontTrait(
				.italicFontMask,
				formatterAttribute: .italicAttributeName,
				baseFont: baseFont,
				range: range
			)
		case .monospace:
			addAttribute(formatterKey(.monospaceAttributeName), value: true, range: range)
			addAttribute(.font, value: monospaceFontMatching(baseFont), range: range)
		case .underline:
			addAttribute(formatterKey(.underlineAttributeName), value: true, range: range)
			addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: range)
		case .strikethrough:
			addAttribute(formatterKey(.strikethroughAttributeName), value: true, range: range)
			addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: range)
		case .foregroundColor:
			addIRCColor(
				value,
				formatterAttribute: .foregroundColorAttributeName,
				appKitAttribute: .foregroundColor,
				range: range
			)
		case .backgroundColor:
			addIRCColor(
				value,
				formatterAttribute: .backgroundColorAttributeName,
				appKitAttribute: .backgroundColor,
				range: range
			)
		case .spoiler:
			if let value {
				addAttribute(formatterKey(.spoilerAttributeName), value: value, range: range)
			}
		@unknown default:
			break
		}
	}

	func setIRCFormatterAttribute(
		_ effect: TextFormatterEffectType,
		value: Any?,
		range limitRange: NSRange
	) {
		enumerateAttributes(in: limitRange, options: .reverse) { attributes, effectiveRange, _ in
			applyIRCFormatterAttribute(effect, value: value, attributes: attributes, range: effectiveRange)
		}
	}

	func removeIRCFormatterAttribute(_ effect: TextFormatterEffectType, range limitRange: NSRange) {
		enumerateAttributes(in: limitRange, options: .reverse) { attributes, effectiveRange, _ in
			/* Only the two trait effects need a font: a run without one still
			 has its underline, strikethrough, colours and spoiler removed. */
			let baseFont = attributes[.font] as? NSFont

			switch effect {
			case .none:
				break
			case .bold:
				if let baseFont, baseFont.hasTrait(.boldFontMask) {
					addAttribute(
						.font,
						value: NSFontManager.shared.convert(baseFont, toNotHaveTrait: .boldFontMask),
						range: effectiveRange
					)
					removeAttribute(
						formatterKey(TextFormatterAttributeName.boldAttributeName), range: effectiveRange
					)
				}
			case .italic:
				if let baseFont, baseFont.hasTrait(.italicFontMask) {
					addAttribute(
						.font,
						value: NSFontManager.shared.convert(baseFont, toNotHaveTrait: .italicFontMask),
						range: effectiveRange
					)
					removeAttribute(
						formatterKey(TextFormatterAttributeName.italicAttributeName), range: effectiveRange
					)
				}
			case .monospace:
				removeAttribute(.font, range: effectiveRange)
				removeAttribute(
					formatterKey(TextFormatterAttributeName.monospaceAttributeName), range: effectiveRange
				)
			case .underline:
				removeAttribute(.underlineStyle, range: effectiveRange)
				removeAttribute(
					formatterKey(TextFormatterAttributeName.underlineAttributeName), range: effectiveRange
				)
			case .strikethrough:
				removeAttribute(.strikethroughStyle, range: effectiveRange)
				removeAttribute(
					formatterKey(TextFormatterAttributeName.strikethroughAttributeName), range: effectiveRange
				)
			case .foregroundColor:
				removeAttribute(.foregroundColor, range: effectiveRange)
				removeAttribute(
					formatterKey(TextFormatterAttributeName.foregroundColorAttributeName), range: effectiveRange
				)
			case .backgroundColor:
				removeAttribute(.backgroundColor, range: effectiveRange)
				removeAttribute(
					formatterKey(TextFormatterAttributeName.backgroundColorAttributeName), range: effectiveRange
				)
			case .spoiler:
				removeAttribute(formatterKey(TextFormatterAttributeName.spoilerAttributeName), range: effectiveRange)
			@unknown default:
				break
			}
		}
	}
}
