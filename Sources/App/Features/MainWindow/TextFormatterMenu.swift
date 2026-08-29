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

import AppKit

/// The IRC formatting menu in `TVCMainWindow.xib` carries its own tag
/// vocabulary, unrelated to `MenuCommand`'s: items 0…15 are colour palette
/// indices and the rest are the commands below.
public enum TextFormatterCommand: Int, CaseIterable, Sendable {
	case bold = 100
	case italics = 101
	case monospace = 102
	case spoiler = 103
	case strikethrough = 104
	case underline = 105
	case colorSeparator = 106
	case foregroundColorSet = 107
	case foregroundColorMissing = 108
	case backgroundColorSet = 109
	case backgroundColorMissing = 110
	case rainbowColor = 299
	case hexColor = 300
}

@objc(TVCTextViewIRCFormattingMenu)
@MainActor
public final class TextViewIRCFormattingMenu: NSObject, NSMenuItemValidation {
	@IBOutlet public var formatterMenu: NSMenuItem!
	@IBOutlet public var foregroundColorMenu: NSMenu!
	@IBOutlet public var backgroundColorMenu: NSMenu!

	private var observingColorPanel = false

	private var hasConfigured = false

	/// Nib-time configuration, run by the main window once the nib's outlets
	/// are connected. `awakeFromNib` is nonisolated and could only reach the
	/// colour menus behind a runtime assumption.
	public func configure() {
		guard hasConfigured == false else {
			return
		}

		hasConfigured = true
		generateColorList()
	}

	private var textField: TextViewWithIRCFormatter? {
		guard let firstResponder = NSApp.keyWindow?.firstResponder as? TextViewWithIRCFormatter else {
			return nil
		}

		return firstResponder
	}

	@objc public var firstResponderSupportsFormatting: Bool {
		textField != nil
	}

	public func validateMenuItem(_ item: NSMenuItem) -> Bool {
		guard textField != nil else {
			return false
		}

		switch TextFormatterCommand(rawValue: item.tag) {
		case .bold:
			let boldText = textIsBold
			item.state = boldText ? .on : .off
			item.action =
				boldText
					? #selector(removeBoldCharFromTextBox(_:))
					: #selector(insertBoldCharIntoTextBox(_:))
			return true

		case .italics:
			let italicText = textIsItalicized
			item.state = italicText ? .on : .off
			item.action =
				italicText
					? #selector(removeItalicCharFromTextBox(_:))
					: #selector(insertItalicCharIntoTextBox(_:))
			return true

		case .monospace:
			let monospaceText = textIsMonospace
			item.state = monospaceText ? .on : .off
			item.action =
				monospaceText
					? #selector(removeMonospaceCharFromTextBox(_:))
					: #selector(insertMonospaceCharIntoTextBox(_:))
			return true

		case .spoiler:
			let spoilerText = textHasSpoiler
			item.state = spoilerText ? .on : .off
			item.action =
				spoilerText
					? #selector(removeSpoilerCharFromTextBox(_:))
					: #selector(insertSpoilerCharIntoTextBox(_:))
			return true

		case .strikethrough:
			let struckthroughText = textIsStruckthrough
			item.state = struckthroughText ? .on : .off
			item.action =
				struckthroughText
					? #selector(removeStrikethroughCharFromTextBox(_:))
					: #selector(insertStrikethroughCharIntoTextBox(_:))
			return true

		case .underline:
			let underlineText = textIsUnderlined
			item.state = underlineText ? .on : .off
			item.action =
				underlineText
					? #selector(removeUnderlineCharFromTextBox(_:))
					: #selector(insertUnderlineCharIntoTextBox(_:))
			return true

		case .foregroundColorMissing:
			item.isHidden = textHasForegroundColor
			return true

		case .foregroundColorSet:
			item.isHidden = textHasForegroundColor == false
			/* Do not enable menu item when there is spoiler */
			return textHasSpoiler == false

		case .backgroundColorMissing:
			item.isHidden = textHasBackgroundColor
			/* Require foreground color before background color can be set */
			return textHasForegroundColor

		case .backgroundColorSet:
			item.isHidden = textHasBackgroundColor == false
			return textHasSpoiler == false

		case .colorSeparator, .rainbowColor, .hexColor, nil:
			break
		}

		return true
	}

	@IBAction @objc(emptyAction:)
	public func emptyAction(_: Any?) {
		/* Empty action used to validate submenus */
	}

	// MARK: - Menu Generation

	private func generateColorList() {
		/* While we could technically load this from a file; we don't need to.
		 That just adds extra space to the app when we already need to have an
		 array of colors in the binary. */
		let colorList = NSColorList(name: ApplicationStrings.ircColors)

		for (index, color) in NSColor.formatterColors.enumerated() {
			colorList.setColor(color, forKey: ApplicationStrings.ircColor(at: index))
		}

		NSColorPanel.shared.attachColorList(colorList)
	}

	// MARK: - Formatting Properties

	private func propertyIsSet(_ formatterEffect: IRCTextFormatterEffectType) -> Bool {
		guard let textField else {
			return false
		}

		let selectedTextRange = textField.selectedRange()
		return textField.attributedString().ircFormatterAttributeSet(inRange: formatterEffect, range: selectedTextRange)
	}

	@objc public var textIsBold: Bool {
		propertyIsSet(.bold)
	}

	@objc public var textIsItalicized: Bool {
		propertyIsSet(.italic)
	}

	@objc public var textIsMonospace: Bool {
		propertyIsSet(.monospace)
	}

	@objc public var textIsStruckthrough: Bool {
		propertyIsSet(.strikethrough)
	}

	@objc public var textIsUnderlined: Bool {
		propertyIsSet(.underline)
	}

	@objc public var textHasForegroundColor: Bool {
		propertyIsSet(.foregroundColor)
	}

	@objc public var textHasBackgroundColor: Bool {
		propertyIsSet(.backgroundColor)
	}

	@objc public var textHasSpoiler: Bool {
		propertyIsSet(.spoiler)
	}

	// MARK: - Formatting Storage Helpers

	private func applyEffectToTextBox(
		_ formatterEffect: IRCTextFormatterEffectType,
		withValue value: Any?,
		inRange limitRange: NSRange
	) {
		guard let stringMutableCopy = mutableString(at: limitRange) else {
			return
		}

		applyEffect(formatterEffect, withValue: value, to: stringMutableCopy)
		applyAttributedStringToTextBox(stringMutableCopy, inRange: limitRange)

		if value == nil, formatterEffect == .foregroundColor || formatterEffect == .spoiler {
			textField?.resetFontColor(in: limitRange)
		}

		if formatterEffect == .monospace, value == nil {
			textField?.resetFont(in: limitRange)
		}
	}

	private func mutableString(at limitRange: NSRange) -> NSMutableAttributedString? {
		guard limitRange.location != NSNotFound, limitRange.length > 0, let textField else {
			return nil
		}

		let stringSubstring = textField.attributedString().attributedSubstring(from: limitRange)
		return stringSubstring.mutableCopy() as? NSMutableAttributedString
	}

	private func applyEffect(
		_ formatterEffect: IRCTextFormatterEffectType,
		withValue value: Any?,
		to mutableString: NSMutableAttributedString
	) {
		let fullRange = NSRange(location: 0, length: mutableString.length)
		applyEffect(formatterEffect, withValue: value, inRange: fullRange, to: mutableString)
	}

	private func applyEffect(
		_ formatterEffect: IRCTextFormatterEffectType,
		withValue value: Any?,
		inRange limitRange: NSRange,
		to mutableString: NSMutableAttributedString
	) {
		if let value {
			mutableString.setIRCFormatterAttribute(formatterEffect, value: value, range: limitRange)
		} else {
			mutableString.removeIRCFormatterAttribute(formatterEffect, range: limitRange)
		}
	}

	private func applyAttributedStringToTextBox(
		_ mutableString: NSMutableAttributedString,
		inRange limitRange: NSRange
	) {
		guard let textField else {
			return
		}

		guard textField.shouldChangeText(in: limitRange, replacementString: mutableString.string) else {
			return
		}

		textField.textStorage?.replaceCharacters(in: limitRange, with: mutableString)
		textField.didChangeText()
		textField.setSelectedRange(limitRange)
	}

	// MARK: - Add Formatting

	@IBAction @objc(insertBoldCharIntoTextBox:)
	public func insertBoldCharIntoTextBox(_: Any?) {
		guard let textField else {
			return
		}

		applyEffectToTextBox(.bold, withValue: true, inRange: textField.selectedRange())
	}

	@IBAction @objc(insertItalicCharIntoTextBox:)
	public func insertItalicCharIntoTextBox(_: Any?) {
		guard let textField else {
			return
		}

		applyEffectToTextBox(.italic, withValue: true, inRange: textField.selectedRange())
	}

	@IBAction @objc(insertMonospaceCharIntoTextBox:)
	public func insertMonospaceCharIntoTextBox(_: Any?) {
		guard let textField else {
			return
		}

		applyEffectToTextBox(.monospace, withValue: true, inRange: textField.selectedRange())
	}

	@IBAction @objc(insertStrikethroughCharIntoTextBox:)
	public func insertStrikethroughCharIntoTextBox(_: Any?) {
		guard let textField else {
			return
		}

		applyEffectToTextBox(.strikethrough, withValue: true, inRange: textField.selectedRange())
	}

	@IBAction @objc(insertUnderlineCharIntoTextBox:)
	public func insertUnderlineCharIntoTextBox(_: Any?) {
		guard let textField else {
			return
		}

		applyEffectToTextBox(.underline, withValue: true, inRange: textField.selectedRange())
	}

	@IBAction @objc(insertForegroundColorCharIntoTextBox:)
	public func insertForegroundColorCharIntoTextBox(_ sender: Any?) {
		guard let sender = sender as? NSMenuItem else {
			return
		}

		if TextFormatterCommand(rawValue: sender.tag) == .rainbowColor {
			insertRainbowColorCharInfoTextBox(asForegroundColor: true)
			return
		}

		if TextFormatterCommand(rawValue: sender.tag) == .hexColor {
			presentColorPanel(
				with: #selector(foregroundColorPanelColorChanged(_:)),
				initialColor: .formatterWhiteColor
			)
			return
		}

		guard let textField else {
			return
		}

		applyEffectToTextBox(
			.foregroundColor,
			withValue: NSNumber(value: sender.tag),
			inRange: textField.selectedRange()
		)
	}

	@IBAction @objc(insertBackgroundColorCharIntoTextBox:)
	public func insertBackgroundColorCharIntoTextBox(_ sender: Any?) {
		guard let sender = sender as? NSMenuItem else {
			return
		}

		if TextFormatterCommand(rawValue: sender.tag) == .rainbowColor {
			insertRainbowColorCharInfoTextBox(asForegroundColor: false)
			return
		}

		if TextFormatterCommand(rawValue: sender.tag) == .hexColor {
			presentColorPanel(
				with: #selector(backgroundColorPanelColorChanged(_:)),
				initialColor: .formatterBlackColor
			)
			return
		}

		guard let textField else {
			return
		}

		applyEffectToTextBox(
			.backgroundColor,
			withValue: NSNumber(value: sender.tag),
			inRange: textField.selectedRange()
		)
	}

	private func insertRainbowColorCharInfoTextBox(asForegroundColor: Bool) {
		guard let textField else {
			return
		}

		let selectedTextRange = textField.selectedRange()

		guard let mutableStringCopy = mutableString(at: selectedTextRange) else {
			return
		}

		mutableStringCopy.beginEditing()

		var rainbowArrayIndex = 0
		let colorCodes: [UInt] = [4, 7, 8, 3, 12, 2, 6]

		/* Coloured by composed character sequence, not by UTF-16 unit: a
		 surrogate pair or a combining sequence used to be split across two
		 colour codes, which broke the character. */
		mutableStringCopy.string.enumerateSubstrings(
			in: mutableStringCopy.string.startIndex ..< mutableStringCopy.string.endIndex,
			options: .byComposedCharacterSequences
		) { [self] _, substringRange, _, _ in
			let currentColorCode = colorCodes[rainbowArrayIndex % colorCodes.count]
			let currentCharacterRange = NSRange(substringRange, in: mutableStringCopy.string)

			applyEffect(
				asForegroundColor ? .foregroundColor : .backgroundColor,
				withValue: NSNumber(value: currentColorCode),
				inRange: currentCharacterRange,
				to: mutableStringCopy
			)

			rainbowArrayIndex += 1
		}

		mutableStringCopy.endEditing()
		applyAttributedStringToTextBox(mutableStringCopy, inRange: selectedTextRange)
	}

	/** The color panel is shared with every other user of it in the app.
	 While it is open on our behalf it sends its action to us; once it
	 closes the target and action are cleared so a later, unrelated
	 presentation does not keep formatting the input field. */
	private func presentColorPanel(with action: Selector, initialColor: NSColor) {
		let colorPanel = NSColorPanel.shared

		colorPanel.setTarget(self)
		colorPanel.setAction(action)
		colorPanel.showsAlpha = false
		colorPanel.mode = .colorList
		colorPanel.color = initialColor

		if observingColorPanel == false {
			observingColorPanel = true

			NotificationCenter.default.addObserver(
				self,
				selector: #selector(colorPanelWillClose(_:)),
				name: NSWindow.willCloseNotification,
				object: colorPanel
			)
		}

		colorPanel.orderFront(nil)
	}

	@objc private func colorPanelWillClose(_ notification: Notification) {
		guard let colorPanel = notification.object as? NSColorPanel else {
			return
		}

		observingColorPanel = false

		NotificationCenter.default.removeObserver(
			self,
			name: NSWindow.willCloseNotification,
			object: colorPanel
		)

		/* NSColorPanel has no target getter, so this cannot check whether
		 another caller took the panel over in the meantime. */
		colorPanel.setTarget(nil)
		colorPanel.setAction(nil)
	}

	@objc private func foregroundColorPanelColorChanged(_ sender: NSColorPanel) {
		guard let textField else {
			return
		}

		let selectedTextRange = textField.selectedRange()
		let color = sender.color
		let colorDigit = NSColor.formatterColors.firstIndex(of: color)

		if let colorDigit {
			applyEffectToTextBox(
				.foregroundColor,
				withValue: NSNumber(value: colorDigit),
				inRange: selectedTextRange
			)
		} else {
			applyEffectToTextBox(.foregroundColor, withValue: color, inRange: selectedTextRange)
		}
	}

	@objc private func backgroundColorPanelColorChanged(_ sender: NSColorPanel) {
		guard let textField else {
			return
		}

		let selectedTextRange = textField.selectedRange()
		let color = sender.color
		let colorDigit = NSColor.formatterColors.firstIndex(of: color)

		if let colorDigit {
			applyEffectToTextBox(
				.backgroundColor,
				withValue: NSNumber(value: colorDigit),
				inRange: selectedTextRange
			)
		} else {
			applyEffectToTextBox(.backgroundColor, withValue: color, inRange: selectedTextRange)
		}
	}

	@IBAction @objc(insertSpoilerCharIntoTextBox:)
	public func insertSpoilerCharIntoTextBox(_: Any?) {
		guard let textField else {
			return
		}

		let selectedTextRange = textField.selectedRange()

		applyEffectToTextBox(.spoiler, withValue: true, inRange: selectedTextRange)
		applyEffectToTextBox(.foregroundColor, withValue: NSNumber(value: 14), inRange: selectedTextRange)
		applyEffectToTextBox(.backgroundColor, withValue: NSNumber(value: 14), inRange: selectedTextRange)
	}

	// MARK: - Remove Formatting

	@IBAction @objc(removeBoldCharFromTextBox:)
	public func removeBoldCharFromTextBox(_: Any?) {
		guard let textField else {
			return
		}

		applyEffectToTextBox(.bold, withValue: nil, inRange: textField.selectedRange())
	}

	@IBAction @objc(removeItalicCharFromTextBox:)
	public func removeItalicCharFromTextBox(_: Any?) {
		guard let textField else {
			return
		}

		applyEffectToTextBox(.italic, withValue: nil, inRange: textField.selectedRange())
	}

	@IBAction @objc(removeMonospaceCharFromTextBox:)
	public func removeMonospaceCharFromTextBox(_: Any?) {
		guard let textField else {
			return
		}

		applyEffectToTextBox(.monospace, withValue: nil, inRange: textField.selectedRange())
	}

	@IBAction @objc(removeStrikethroughCharFromTextBox:)
	public func removeStrikethroughCharFromTextBox(_: Any?) {
		guard let textField else {
			return
		}

		applyEffectToTextBox(.strikethrough, withValue: nil, inRange: textField.selectedRange())
	}

	@IBAction @objc(removeUnderlineCharFromTextBox:)
	public func removeUnderlineCharFromTextBox(_: Any?) {
		guard let textField else {
			return
		}

		applyEffectToTextBox(.underline, withValue: nil, inRange: textField.selectedRange())
	}

	@IBAction @objc(removeForegroundColorCharFromTextBox:)
	public func removeForegroundColorCharFromTextBox(_: Any?) {
		guard let textField else {
			return
		}

		applyEffectToTextBox(.foregroundColor, withValue: nil, inRange: textField.selectedRange())
	}

	@IBAction @objc(removeBackgroundColorCharFromTextBox:)
	public func removeBackgroundColorCharFromTextBox(_: Any?) {
		guard let textField else {
			return
		}

		applyEffectToTextBox(.backgroundColor, withValue: nil, inRange: textField.selectedRange())
	}

	@IBAction @objc(removeSpoilerCharFromTextBox:)
	public func removeSpoilerCharFromTextBox(_: Any?) {
		guard let textField else {
			return
		}

		let selectedTextRange = textField.selectedRange()

		applyEffectToTextBox(.foregroundColor, withValue: nil, inRange: selectedTextRange)
		applyEffectToTextBox(.backgroundColor, withValue: nil, inRange: selectedTextRange)
		applyEffectToTextBox(.spoiler, withValue: nil, inRange: selectedTextRange)
	}
}
