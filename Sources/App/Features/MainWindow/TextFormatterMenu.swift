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

/// The IRC formatting menu carries its own tag vocabulary, unrelated to
/// `MenuCommand`'s: items 0…15 are colour palette indices and the rest are the
/// commands below.
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

@MainActor
public final class TextViewIRCFormattingMenu: NSObject, NSMenuItemValidation {
	public private(set) var formatterMenu: NSMenuItem!
	public private(set) var foregroundColorMenu: NSMenu!
	public private(set) var backgroundColorMenu: NSMenu!

	/// Which presentation of the shared colour panel is current. The close
	/// notification arrives a turn late, so a teardown has to be able to tell
	/// whether the panel it is tearing down is still the one it presented.
	private var colorPanelPresentation = 0
	/// The shared colour panel's close notification, held while the panel is up.
	private let notifications = NotificationSubscriptions()

	private var hasConfigured = false

	override public init() {
		super.init()
		installMenus()
	}

	private func installMenus() {
		let root = NSMenu(title: MainWindowStrings.Formatting.menuTitle)
		formatterMenu = NSMenuItem(title: root.title, action: nil, keyEquivalent: "")
		formatterMenu.submenu = root

		addFormattingItem(
			MainWindowStrings.Formatting.bold,
			command: .bold,
			action: #selector(insertBoldCharIntoTextBox),
			to: root
		)
		addFormattingItem(
			MainWindowStrings.Formatting.italics,
			command: .italics,
			action: #selector(insertItalicCharIntoTextBox),
			to: root
		)
		addFormattingItem(
			MainWindowStrings.Formatting.monospace,
			command: .monospace,
			action: #selector(insertMonospaceCharIntoTextBox),
			to: root
		)
		addFormattingItem(
			MainWindowStrings.Formatting.spoiler,
			command: .spoiler,
			action: #selector(insertSpoilerCharIntoTextBox),
			to: root
		)
		addFormattingItem(
			MainWindowStrings.Formatting.strikethrough,
			command: .strikethrough,
			action: #selector(insertStrikethroughCharIntoTextBox),
			to: root
		)
		addFormattingItem(
			MainWindowStrings.Formatting.underline,
			command: .underline,
			action: #selector(insertUnderlineCharIntoTextBox),
			to: root
		)
		root.addItem(.separator())

		foregroundColorMenu = colorMenu(
			title: MainWindowStrings.Formatting.textColor,
			action: #selector(insertForegroundColorCharIntoTextBox)
		)
		addColorItems(
			to: root,
			title: MainWindowStrings.Formatting.textColor,
			setCommand: .foregroundColorSet,
			missingCommand: .foregroundColorMissing,
			removeAction: #selector(removeForegroundColorCharFromTextBox),
			menu: foregroundColorMenu
		)

		backgroundColorMenu = colorMenu(
			title: MainWindowStrings.Formatting.backgroundColor,
			action: #selector(insertBackgroundColorCharIntoTextBox)
		)
		addColorItems(
			to: root,
			title: MainWindowStrings.Formatting.backgroundColor,
			setCommand: .backgroundColorSet,
			missingCommand: .backgroundColorMissing,
			removeAction: #selector(removeBackgroundColorCharFromTextBox),
			menu: backgroundColorMenu
		)
	}

	private func addFormattingItem(
		_ title: String,
		command: TextFormatterCommand,
		action: Selector,
		to menu: NSMenu
	) {
		let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
		item.tag = command.rawValue
		item.target = self
		menu.addItem(item)
	}

	private func addColorItems(
		to root: NSMenu,
		title: String,
		setCommand: TextFormatterCommand,
		missingCommand: TextFormatterCommand,
		removeAction: Selector,
		menu: NSMenu
	) {
		let remove = NSMenuItem(title: title, action: removeAction, keyEquivalent: "")
		remove.tag = setCommand.rawValue
		remove.target = self
		remove.state = .on
		remove.isHidden = true
		root.addItem(remove)

		let choose = NSMenuItem(title: title, action: #selector(emptyAction), keyEquivalent: "")
		choose.tag = missingCommand.rawValue
		choose.target = self
		choose.submenu = menu
		root.addItem(choose)
	}

	private func colorMenu(title: String, action: Selector) -> NSMenu {
		let menu = NSMenu(title: title)
		for index in NSColor.formatterColors.indices {
			let item = NSMenuItem(
				title: ApplicationStrings.ircColor(at: index),
				action: action,
				keyEquivalent: ""
			)
			item.tag = index
			item.target = self
			menu.addItem(item)
		}

		menu.addItem(.separator())
		let rainbow = NSMenuItem(title: MainWindowStrings.Formatting.rainbow, action: action, keyEquivalent: "")
		rainbow.tag = TextFormatterCommand.rainbowColor.rawValue
		rainbow.target = self
		menu.addItem(rainbow)

		let custom = NSMenuItem(title: MainWindowStrings.Formatting.other, action: action, keyEquivalent: "")
		custom.tag = TextFormatterCommand.hexColor.rawValue
		custom.target = self
		menu.addItem(custom)
		return menu
	}

	/// Completes menu configuration once the application graph is available.
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

	public var firstResponderSupportsFormatting: Bool {
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

	public var textIsBold: Bool {
		propertyIsSet(.bold)
	}

	public var textIsItalicized: Bool {
		propertyIsSet(.italic)
	}

	public var textIsMonospace: Bool {
		propertyIsSet(.monospace)
	}

	public var textIsStruckthrough: Bool {
		propertyIsSet(.strikethrough)
	}

	public var textIsUnderlined: Bool {
		propertyIsSet(.underline)
	}

	public var textHasForegroundColor: Bool {
		propertyIsSet(.foregroundColor)
	}

	public var textHasBackgroundColor: Bool {
		propertyIsSet(.backgroundColor)
	}

	public var textHasSpoiler: Bool {
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

		colorPanelPresentation += 1
		let presentation = colorPanelPresentation

		notifications.cancelAll()
		notifications.observe(NSWindow.willCloseNotification, object: colorPanel) { [weak self] notification in
			self?.colorPanelWillClose(notification, from: presentation)
		}

		colorPanel.orderFront(nil)
	}

	/** The notification lands a turn after the panel closed, by which time this
	 menu may have presented the shared panel again. Clearing the target off
	 that new presentation would leave the picker up and every colour it reports
	 going nowhere, so a teardown only runs for the presentation it belongs to. */
	private func colorPanelWillClose(_ notification: Notification, from presentation: Int) {
		guard let colorPanel = notification.object as? NSColorPanel,
		      presentation == colorPanelPresentation
		else {
			return
		}

		notifications.cancelAll()

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

	@IBAction
	public func removeBoldCharFromTextBox(_: Any?) {
		guard let textField else {
			return
		}

		applyEffectToTextBox(.bold, withValue: nil, inRange: textField.selectedRange())
	}

	@IBAction
	public func removeItalicCharFromTextBox(_: Any?) {
		guard let textField else {
			return
		}

		applyEffectToTextBox(.italic, withValue: nil, inRange: textField.selectedRange())
	}

	@IBAction
	public func removeMonospaceCharFromTextBox(_: Any?) {
		guard let textField else {
			return
		}

		applyEffectToTextBox(.monospace, withValue: nil, inRange: textField.selectedRange())
	}

	@IBAction
	public func removeStrikethroughCharFromTextBox(_: Any?) {
		guard let textField else {
			return
		}

		applyEffectToTextBox(.strikethrough, withValue: nil, inRange: textField.selectedRange())
	}

	@IBAction
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

	@IBAction
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
