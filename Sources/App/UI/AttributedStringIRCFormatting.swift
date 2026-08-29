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
public extension NSMutableAttributedString {
	private func addIRCFontTrait(
		_ trait: NSFontTraitMask,
		formatterAttribute: IRCTextFormatterAttributeName,
		baseFont: NSFont?,
		range: NSRange
	) {
		guard let baseFont else {
			return
		}

		let font = if baseFont.textual_fontTraitIsSet(trait) {
			baseFont
		} else {
			NSFontManager.shared.convert(baseFont, toHaveTrait: trait)
		}

		addAttribute(formatterKey(formatterAttribute), value: true, range: range)
		addAttribute(.font, value: font, range: range)
	}

	private func addIRCColor(
		_ value: Any?,
		formatterAttribute: IRCTextFormatterAttributeName,
		appKitAttribute: NSAttributedString.Key,
		range: NSRange
	) {
		if let colorCode = (value as? NSNumber)?.intValue,
		   (0 ... colorHighestDigit).contains(colorCode)
		{
			addAttribute(formatterKey(formatterAttribute), value: colorCode, range: range)
			addAttribute(appKitAttribute, value: TVCLogRenderer.mapColorCode(UInt(colorCode)), range: range)
		} else if let color = value as? NSColor {
			addAttribute(formatterKey(formatterAttribute), value: color, range: range)
			addAttribute(appKitAttribute, value: color, range: range)
		}
	}

	private func applyIRCFormatterAttribute(
		_ effect: IRCTextFormatterEffectType,
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
		_ effect: IRCTextFormatterEffectType,
		value: Any?,
		range limitRange: NSRange
	) {
		enumerateAttributes(in: limitRange, options: .reverse) { attributes, effectiveRange, _ in
			applyIRCFormatterAttribute(effect, value: value, attributes: attributes, range: effectiveRange)
		}
	}

	func removeIRCFormatterAttribute(_ effect: IRCTextFormatterEffectType, range limitRange: NSRange) {
		enumerateAttributes(in: limitRange, options: .reverse) { attributes, effectiveRange, _ in
			guard var baseFont = attributes[.font] as? NSFont else {
				return
			}

			switch effect {
			case .none:
				break
			case .bold:
				if baseFont.textual_fontTraitIsSet(.boldFontMask) {
					baseFont = NSFontManager.shared.convert(baseFont, toNotHaveTrait: .boldFontMask)

					addAttribute(.font, value: baseFont, range: effectiveRange)
					removeAttribute(
						formatterKey(IRCTextFormatterAttributeName.boldAttributeName), range: effectiveRange
					)
				}
			case .italic:
				if baseFont.textual_fontTraitIsSet(.italicFontMask) {
					baseFont = NSFontManager.shared.convert(baseFont, toNotHaveTrait: .italicFontMask)

					addAttribute(.font, value: baseFont, range: effectiveRange)
					removeAttribute(
						formatterKey(IRCTextFormatterAttributeName.italicAttributeName), range: effectiveRange
					)
				}
			case .monospace:
				removeAttribute(.font, range: effectiveRange)
				removeAttribute(
					formatterKey(IRCTextFormatterAttributeName.monospaceAttributeName), range: effectiveRange
				)
			case .underline:
				removeAttribute(.underlineStyle, range: effectiveRange)
				removeAttribute(
					formatterKey(IRCTextFormatterAttributeName.underlineAttributeName), range: effectiveRange
				)
			case .strikethrough:
				removeAttribute(.strikethroughStyle, range: effectiveRange)
				removeAttribute(
					formatterKey(IRCTextFormatterAttributeName.strikethroughAttributeName), range: effectiveRange
				)
			case .foregroundColor:
				/* Matches the original implementation, which removes the AppKit
				 background color when clearing the IRC foreground formatter. */
				removeAttribute(.backgroundColor, range: effectiveRange)
				removeAttribute(
					formatterKey(IRCTextFormatterAttributeName.foregroundColorAttributeName), range: effectiveRange
				)
			case .backgroundColor:
				removeAttribute(.backgroundColor, range: effectiveRange)
				removeAttribute(
					formatterKey(IRCTextFormatterAttributeName.backgroundColorAttributeName), range: effectiveRange
				)
			case .spoiler:
				removeAttribute(formatterKey(IRCTextFormatterAttributeName.spoilerAttributeName), range: effectiveRange)
			@unknown default:
				break
			}
		}
	}
}
