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
	case foregroundColorSet = 107
	case foregroundColorMissing = 108
	case backgroundColorSet = 109
	case backgroundColorMissing = 110
	case rainbowColor = 299
	case hexColor = 300

	/// The character effect a command turns on and off, where it is a plain
	/// one. Spoiler is not: it carries two colours with it, and the colour
	/// commands take a value rather than a state.
	var effect: IRCTextFormatterEffectType? {
		switch self {
		case .bold: .bold
		case .italics: .italic
		case .monospace: .monospace
		case .strikethrough: .strikethrough
		case .underline: .underline
		case .spoiler: .spoiler
		case .foregroundColorSet, .foregroundColorMissing: .foregroundColor
		case .backgroundColorSet, .backgroundColorMissing: .backgroundColor
		case .rainbowColor, .hexColor: nil
		}
	}

	/// What the Format menu calls the effect.
	var menuTitle: String {
		switch self {
		case .bold: MainWindowStrings.Formatting.bold
		case .italics: MainWindowStrings.Formatting.italics
		case .underline: MainWindowStrings.Formatting.underline
		case .strikethrough: MainWindowStrings.Formatting.strikethrough
		case .monospace: MainWindowStrings.Formatting.monospace
		case .spoiler: MainWindowStrings.Formatting.spoiler
		case .foregroundColorSet, .foregroundColorMissing: MainWindowStrings.Formatting.textColor
		case .backgroundColorSet, .backgroundColorMissing: MainWindowStrings.Formatting.backgroundColor
		case .rainbowColor: MainWindowStrings.Formatting.rainbow
		case .hexColor: MainWindowStrings.Formatting.other
		}
	}

	/// Bold, Italic and Underline carry the shortcuts every macOS text editor
	/// binds them to. The rest carry none: a chat client has no claim on more
	/// of the Command row than the three everyone already knows.
	var keyEquivalent: String {
		switch self {
		case .bold: "b"
		case .italics: "i"
		case .underline: "u"
		default: ""
		}
	}
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

	private var hasAttachedColorList = false
	/// Set by the window that installs the menu; see `attach(to:)`.
	private weak var hostWindow: NSWindow?

	/// The six character effects, in the order the menu offers them, with the
	/// three that carry a key equivalent first.
	private static let formattingCommands: [TextFormatterCommand] = [
		.bold, .italics, .underline, .strikethrough, .monospace, .spoiler,
	]

	override public init() {
		super.init()
		installMenus()
	}

	private func installMenus() {
		let root = NSMenu(title: MainWindowStrings.Formatting.menuTitle)
		formatterMenu = NSMenuItem(title: root.title, action: nil, keyEquivalent: "")
		formatterMenu.submenu = root

		for command in Self.formattingCommands {
			let item = NSMenuItem(
				title: command.menuTitle,
				action: #selector(toggleFormatting(_:)),
				keyEquivalent: command.keyEquivalent
			)
			item.keyEquivalentModifierMask = command.keyEquivalent.isEmpty ? [] : .command
			item.tag = command.rawValue
			item.target = self
			root.addItem(item)
		}

		root.addItem(.separator())

		foregroundColorMenu = colorMenu(
			title: TextFormatterCommand.foregroundColorSet.menuTitle,
			action: #selector(insertForegroundColorCharIntoTextBox)
		)
		addColorItems(
			to: root,
			setCommand: .foregroundColorSet,
			missingCommand: .foregroundColorMissing,
			removeAction: #selector(removeForegroundColorCharFromTextBox),
			menu: foregroundColorMenu
		)

		backgroundColorMenu = colorMenu(
			title: TextFormatterCommand.backgroundColorSet.menuTitle,
			action: #selector(insertBackgroundColorCharIntoTextBox)
		)
		addColorItems(
			to: root,
			setCommand: .backgroundColorSet,
			missingCommand: .backgroundColorMissing,
			removeAction: #selector(removeBackgroundColorCharFromTextBox),
			menu: backgroundColorMenu
		)

		installDecorations()
	}

	/** What the menu shows rather than says: a colour swatch beside every
	 colour, the monospace item set in the monospaced face, and the spoiler item
	 drawn the way a spoiler is -- label on label, so it has to be selected to
	 be read. `makeMenu()` copies the items, so the menu bar's Format menu
	 carries them too. */
	private func installDecorations() {
		for menu in [foregroundColorMenu!, backgroundColorMenu!] {
			for item in menu.items where item.isSeparatorItem == false && item.action != nil {
				item.image = Self.colorSwatch(forColorTag: item.tag)
			}
		}

		guard let root = formatterMenu.submenu else { return }
		if let monospaceItem = root.item(withTag: TextFormatterCommand.monospace.rawValue) {
			monospaceItem.attributedTitle = NSAttributedString(
				string: monospaceItem.title,
				attributes: [.font: NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)]
			)
		}
		if let spoilerItem = root.item(withTag: TextFormatterCommand.spoiler.rawValue) {
			spoilerItem.attributedTitle = NSAttributedString(
				string: spoilerItem.title,
				attributes: [
					.font: NSFont.menuFont(ofSize: 0),
					.foregroundColor: NSColor.windowBackgroundColor,
					.backgroundColor: NSColor.labelColor,
				]
			)
		}
	}

	private static func colorSwatch(forColorTag tag: Int) -> NSImage? {
		if TextFormatterCommand(rawValue: tag) == .rainbowColor {
			return NSImage(systemSymbolName: "rainbow", accessibilityDescription: nil)
		}
		let colors = NSColor.formatterColors
		guard tag >= 0, tag < colors.count else { return nil }
		let color = colors[tag]
		let image = NSImage(size: NSSize(width: 16, height: 16), flipped: false) { rect in
			let circle = NSBezierPath(ovalIn: rect.insetBy(dx: 1.5, dy: 1.5))
			color.setFill()
			circle.fill()
			NSColor.separatorColor.withAlphaComponent(0.6).setStroke()
			circle.lineWidth = 1
			circle.stroke()
			return true
		}
		image.isTemplate = false
		return image
	}

	/** A second copy of the formatting menu, for the menu bar's Format menu.

	 An `NSMenu` belongs to one supermenu, so the menu bar cannot hang the same
	 instance the input field's context menu already holds. The copy carries the
	 items' targets, tags, key equivalents and the swatches and styled titles the
	 window decorates them with. */
	public func makeMenu() -> NSMenu? {
		formatterMenu.submenu?.copy() as? NSMenu
	}

	/// The two halves of one colour command: the item that removes the colour
	/// while one is set, and the palette submenu that offers one while none is.
	private func addColorItems(
		to root: NSMenu,
		setCommand: TextFormatterCommand,
		missingCommand: TextFormatterCommand,
		removeAction: Selector,
		menu: NSMenu
	) {
		let title = setCommand.menuTitle
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
		for command in [TextFormatterCommand.rainbowColor, .hexColor] {
			let item = NSMenuItem(title: command.menuTitle, action: action, keyEquivalent: "")
			item.tag = command.rawValue
			item.target = self
			menu.addItem(item)
		}

		return menu
	}

	/** The window whose message field this menu formats.

	 Resolving through the key window loses the field the moment the user needs
	 it most: clicking `NSColorPanel` makes the panel key, so every colour it
	 reported went nowhere and the custom-colour items did nothing at all. A
	 window keeps its own first responder whether or not it is key, so the
	 window that owns the menu is the one to ask. */
	public func attach(to window: NSWindow) {
		hostWindow = window
	}

	private var textField: TextViewWithIRCFormatter? {
		let window = hostWindow ?? NSApp.mainWindow
		return window?.firstResponder as? TextViewWithIRCFormatter
	}

	/** One rule per command instead of six near-identical branches.

	 Each character effect is ticked while it is in force and untouched
	 otherwise; the two colour commands are a set/unset pair, so only the half
	 that applies is shown. */
	public func validateMenuItem(_ item: NSMenuItem) -> Bool {
		guard textField != nil else {
			return false
		}

		switch TextFormatterCommand(rawValue: item.tag) {
		case .bold, .italics, .monospace, .spoiler, .strikethrough, .underline:
			item.state = isSet(TextFormatterCommand(rawValue: item.tag)) ? .on : .off
			return true

		case .foregroundColorMissing:
			item.isHidden = isSet(.foregroundColorSet)
			return true

		case .foregroundColorSet:
			item.isHidden = isSet(.foregroundColorSet) == false
			/* A spoiler owns both colours; changing one of them would show what
			 the spoiler is hiding. */
			return isSet(.spoiler) == false

		case .backgroundColorMissing:
			item.isHidden = isSet(.backgroundColorSet)
			/* A background colour is only meaningful over a foreground one. */
			return isSet(.foregroundColorSet)

		case .backgroundColorSet:
			item.isHidden = isSet(.backgroundColorSet) == false
			return isSet(.spoiler) == false

		case .rainbowColor, .hexColor, nil:
			return true
		}
	}

	@objc(emptyAction:)
	public func emptyAction(_: Any?) {
		/* Empty action used to validate submenus */
	}

	// MARK: - Menu Generation

	/** Puts the IRC palette in the colour panel's list picker, once.

	 Attached from the presentation rather than when the window installs the
	 menu. `NSColorPanel.shared` builds the entire system picker the first time
	 anything asks for it — the colour wheel included, which draws through
	 CoreImage and so loads Metal and its shader caches — and a session that
	 never opens a colour picker has no use for any of that.

	 The list is built here rather than loaded from a file: the colours are
	 already an array in the binary. */
	private func attachColorList() {
		guard hasAttachedColorList == false else {
			return
		}

		hasAttachedColorList = true

		let colorList = NSColorList(name: ApplicationStrings.ircColors)

		for (index, color) in NSColor.formatterColors.enumerated() {
			colorList.setColor(color, forKey: ApplicationStrings.ircColor(at: index))
		}

		NSColorPanel.shared.attachColorList(colorList)
	}

	// MARK: - Formatting state

	/// Whether the effect a command stands for is set across the selection.
	public func isSet(_ command: TextFormatterCommand?) -> Bool {
		guard let effect = command?.effect, let textField else {
			return false
		}

		return textField.attributedString().ircFormatterAttributeSet(
			inRange: effect,
			range: textField.selectedRange()
		)
	}

	/// Turns a character effect on or off across the selection. A spoiler
	/// carries the two colours that hide the text with it.
	public func setEffect(_ command: TextFormatterCommand, enabled: Bool) {
		guard let effect = command.effect, let textField else {
			return
		}

		let range = textField.selectedRange()
		let value: Any? = enabled ? true : nil

		if command == .spoiler {
			let colorValue: Any? = enabled ? NSNumber(value: Self.spoilerColorCode) : nil
			if enabled {
				applyEffectToTextBox(.spoiler, withValue: value, inRange: range)
			}
			applyEffectToTextBox(.foregroundColor, withValue: colorValue, inRange: range)
			applyEffectToTextBox(.backgroundColor, withValue: colorValue, inRange: range)
			if enabled == false {
				applyEffectToTextBox(.spoiler, withValue: nil, inRange: range)
			}
			return
		}

		applyEffectToTextBox(effect, withValue: value, inRange: range)
	}

	/// Reverses the effect the clicked item names.
	@objc public func toggleFormatting(_ sender: Any?) {
		guard let tag = (sender as? NSMenuItem)?.tag,
		      let command = TextFormatterCommand(rawValue: tag)
		else { return }

		setEffect(command, enabled: isSet(command) == false)
	}

	/// The palette entry a spoiler paints itself with, foreground and
	/// background alike, so the text reads as a solid block until it is
	/// selected.
	private static let spoilerColorCode = 14

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

	// MARK: - Colours

	@objc(insertForegroundColorCharIntoTextBox:)
	public func insertForegroundColorCharIntoTextBox(_ sender: Any?) {
		insertColor(from: sender, asForegroundColor: true)
	}

	@objc(insertBackgroundColorCharIntoTextBox:)
	public func insertBackgroundColorCharIntoTextBox(_ sender: Any?) {
		insertColor(from: sender, asForegroundColor: false)
	}

	private func insertColor(from sender: Any?, asForegroundColor: Bool) {
		guard let sender = sender as? NSMenuItem else {
			return
		}

		switch TextFormatterCommand(rawValue: sender.tag) {
		case .rainbowColor:
			insertRainbowColorCharInfoTextBox(asForegroundColor: asForegroundColor)
		case .hexColor:
			presentColorPanel(
				with: asForegroundColor
					? #selector(foregroundColorPanelColorChanged(_:))
					: #selector(backgroundColorPanelColorChanged(_:)),
				initialColor: asForegroundColor ? .formatterWhiteColor : .formatterBlackColor
			)
		default:
			guard let textField else {
				return
			}
			applyEffectToTextBox(
				asForegroundColor ? .foregroundColor : .backgroundColor,
				withValue: NSNumber(value: sender.tag),
				inRange: textField.selectedRange()
			)
		}
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
		 colour codes, which broke the character.

		 Every index below belongs to this one bridged copy. Reading
		 `.string` again would hand back a different String, and an index
		 from one is not valid in another. */
		let text = mutableStringCopy.string

		text.enumerateSubstrings(
			in: text.startIndex ..< text.endIndex,
			options: .byComposedCharacterSequences
		) { [self] _, substringRange, _, _ in
			let currentColorCode = colorCodes[rainbowArrayIndex % colorCodes.count]
			let currentCharacterRange = NSRange(substringRange, in: text)

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
		attachColorList()

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
		applyPanelColor(sender.color, asForegroundColor: true)
	}

	@objc private func backgroundColorPanelColorChanged(_ sender: NSColorPanel) {
		applyPanelColor(sender.color, asForegroundColor: false)
	}

	private func applyPanelColor(_ color: NSColor, asForegroundColor: Bool) {
		guard let textField else {
			return
		}

		let effect: IRCTextFormatterEffectType = asForegroundColor ? .foregroundColor : .backgroundColor
		let selectedTextRange = textField.selectedRange()

		if let colorDigit = NSColor.formatterColors.firstIndex(of: color) {
			applyEffectToTextBox(effect, withValue: NSNumber(value: colorDigit), inRange: selectedTextRange)
		} else {
			applyEffectToTextBox(effect, withValue: color, inRange: selectedTextRange)
		}
	}

	@objc(removeForegroundColorCharFromTextBox:)
	public func removeForegroundColorCharFromTextBox(_: Any?) {
		guard let textField else {
			return
		}

		applyEffectToTextBox(.foregroundColor, withValue: nil, inRange: textField.selectedRange())
	}

	@objc(removeBackgroundColorCharFromTextBox:)
	public func removeBackgroundColorCharFromTextBox(_: Any?) {
		guard let textField else {
			return
		}

		applyEffectToTextBox(.backgroundColor, withValue: nil, inRange: textField.selectedRange())
	}
}
