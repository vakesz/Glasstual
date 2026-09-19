// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit

/// The IRC formatting menu carries its own tag vocabulary, unrelated to
/// `MenuCommand`'s. A colour item's tag is its index in
/// `NSColor.formatterColors`, 0 to 98, and every other item's tag is one of the
/// commands below.
enum TextFormatterCommand: Int, CaseIterable, Sendable {
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
	var effect: TextFormatterEffectKind? {
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
		case .bold: String(localized: .MainWindow.bold)
		case .italics: String(localized: .MainWindow.italics)
		case .underline: String(localized: .MainWindow.underline)
		case .strikethrough: String(localized: .MainWindow.strikethrough)
		case .monospace: String(localized: .MainWindow.monospace)
		case .spoiler: String(localized: .MainWindow.spoiler)
		case .foregroundColorSet, .foregroundColorMissing: String(localized: .MainWindow.textColor)
		case .backgroundColorSet, .backgroundColorMissing: String(localized: .MainWindow.backgroundColor)
		case .rainbowColor: String(localized: .MainWindow.rainbow)
		case .hexColor: String(localized: .MainWindow.other)
		}
	}

	/// Bold, Italic and Underline carry the shortcuts every macOS text editor
	/// binds them to. The rest carry none: a chat session has no claim on more
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

/** The Format menu, and the same menu inside the message field's own context
 menu.

 This owns what the menu is: the items, what they show, whether each one is
 offered and ticked, and which command a click stands for. What a command does to
 the text is ``TextFormatterEditor``'s, and the custom-colour picker is
 ``TextFormatterColorPanel``'s; the menu resolves the field once per command and
 hands it to the first of the two. */
@MainActor
final class TextFormattingMenu: NSObject, NSMenuItemValidation {
	private(set) var formatterMenu: NSMenuItem!
	private(set) var foregroundColorMenu: NSMenu!
	private(set) var backgroundColorMenu: NSMenu!

	private let colorPanel = TextFormatterColorPanel()

	/// Set by the window that installs the menu; see `attach(to:)`.
	private weak var hostWindow: NSWindow?

	/// The six character effects, in the order the menu offers them, with the
	/// three that carry a key equivalent first.
	private static let formattingCommands: [TextFormatterCommand] = [
		.bold, .italics, .underline, .strikethrough, .monospace, .spoiler,
	]

	override init() {
		super.init()
		installMenus()
	}

	private func installMenus() {
		let root = NSMenu(title: String(localized: .MainWindow.ircFormatting))
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
			action: #selector(applyForegroundColor)
		)
		addColorItems(
			to: root,
			setCommand: .foregroundColorSet,
			missingCommand: .foregroundColorMissing,
			removeAction: #selector(clearForegroundColor),
			menu: foregroundColorMenu
		)

		backgroundColorMenu = colorMenu(
			title: TextFormatterCommand.backgroundColorSet.menuTitle,
			action: #selector(applyBackgroundColor)
		)
		addColorItems(
			to: root,
			setCommand: .backgroundColorSet,
			missingCommand: .backgroundColorMissing,
			removeAction: #selector(clearBackgroundColor),
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
				/* The title only numbers the colour, which is the IRC code.
				 VoiceOver reads the colour's name after it, so a reader who
				 cannot see the swatch still knows which colour they pick. */
				if let colorName = item.image?.accessibilityDescription {
					item.setAccessibilityValue(colorName)
				}
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
		guard colors.indices.contains(tag) else { return nil }
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
		image.accessibilityDescription = color.accessibilityName
		return image
	}

	/** A second copy of the formatting menu, for the menu bar's Format menu.

	 An `NSMenu` belongs to one supermenu, so the menu bar cannot hang the same
	 instance the input field's context menu already holds. The copy carries the
	 items' targets, tags, key equivalents and the swatches and styled titles the
	 window decorates them with. */
	func makeMenu() -> NSMenu? {
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

		let choose = NSMenuItem(title: title, action: #selector(validationPlaceholder), keyEquivalent: "")
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

	// MARK: - The field the menu formats

	/** The window whose message field this menu formats.

	 Resolving through the key window loses the field the moment the user needs
	 it most: clicking `NSColorPanel` makes the panel key, so every colour it
	 reported went nowhere and the custom-colour items did nothing at all. A
	 window keeps its own first responder whether or not it is key, so the
	 window that owns the menu is the one to ask. */
	func attach(to window: NSWindow) {
		hostWindow = window
	}

	/// The edit half, pointed at the field that holds the keyboard, or `nil`
	/// where nothing formattable does.
	private var editor: TextFormatterEditor? {
		let window = hostWindow ?? NSApp.mainWindow
		guard let field = window?.firstResponder as? FormattedTextView else { return nil }
		return TextFormatterEditor(field: field)
	}

	// MARK: - Validation

	/** One rule per command instead of six near-identical branches.

	 Each character effect is ticked while it is in force and untouched
	 otherwise; the two colour commands are a set/unset pair, so only the half
	 that applies is shown. */
	func validateMenuItem(_ item: NSMenuItem) -> Bool {
		guard let editor else {
			return false
		}

		let command = TextFormatterCommand(rawValue: item.tag)

		switch command {
		case .bold, .italics, .monospace, .spoiler, .strikethrough, .underline:
			guard let effect = command?.effect else { return true }
			item.state = editor.isSet(effect) ? .on : .off
			return true

		case .foregroundColorMissing:
			item.isHidden = editor.isSet(.foregroundColor)
			return true

		case .foregroundColorSet:
			item.isHidden = editor.isSet(.foregroundColor) == false
			/* A spoiler owns both colours; changing one of them would show what
			 the spoiler is hiding. */
			return editor.isSet(.spoiler) == false

		case .backgroundColorMissing:
			item.isHidden = editor.isSet(.backgroundColor)
			/* A background colour is only meaningful over a foreground one. */
			return editor.isSet(.foregroundColor)

		case .backgroundColorSet:
			item.isHidden = editor.isSet(.backgroundColor) == false
			return editor.isSet(.spoiler) == false

		case .rainbowColor, .hexColor, nil:
			return true
		}
	}

	@objc func validationPlaceholder(_: Any?) {
		/* Empty action used to validate submenus */
	}

	/// Whether the effect a command stands for is set across the selection, for
	/// the keyboard shortcuts the window binds to the two colour commands. A
	/// command with no effect of its own -- rainbow, the custom-colour picker --
	/// never is.
	func isSet(_ command: TextFormatterCommand?) -> Bool {
		guard let effect = command?.effect, let editor else { return false }
		return editor.isSet(effect)
	}

	/// Turns a character effect on or off across the selection.
	func setEffect(_ command: TextFormatterCommand, enabled: Bool) {
		guard let effect = command.effect, let editor else { return }
		editor.setEffect(effect, enabled: enabled)
	}

	// MARK: - Item actions

	/// Reverses the effect the clicked item names.
	@objc func toggleFormatting(_ sender: Any?) {
		guard let tag = (sender as? NSMenuItem)?.tag,
		      let command = TextFormatterCommand(rawValue: tag)
		else { return }

		setEffect(command, enabled: isSet(command) == false)
	}

	@objc func applyForegroundColor(_ sender: Any?) {
		insertColor(from: sender, asForegroundColor: true)
	}

	@objc func applyBackgroundColor(_ sender: Any?) {
		insertColor(from: sender, asForegroundColor: false)
	}

	@objc func clearForegroundColor(_: Any?) {
		guard let editor else { return }
		editor.apply(.foregroundColor, value: nil, in: editor.field.selectedRange())
	}

	@objc func clearBackgroundColor(_: Any?) {
		guard let editor else { return }
		editor.apply(.backgroundColor, value: nil, in: editor.field.selectedRange())
	}

	private func insertColor(from sender: Any?, asForegroundColor: Bool) {
		guard let sender = sender as? NSMenuItem else {
			return
		}

		let effect: TextFormatterEffectKind = asForegroundColor ? .foregroundColor : .backgroundColor

		switch TextFormatterCommand(rawValue: sender.tag) {
		case .rainbowColor:
			editor?.applyRainbow(asForegroundColor: asForegroundColor)
		case .hexColor:
			colorPanel.present(
				startingAt: asForegroundColor ? .formatterWhiteColor : .formatterBlackColor
			) { [weak self] color in
				self?.applyPanelColor(color, as: effect)
			}
		default:
			guard let editor else { return }
			editor.apply(effect, value: NSNumber(value: sender.tag), in: editor.field.selectedRange())
		}
	}

	/** A colour the panel reported, as a palette code where it is one of the IRC
	 colours and as the colour itself otherwise.

	 The field is resolved per report rather than captured when the picker
	 opened: the picker stays up across selections, and the window's own first
	 responder is what says where the colour lands. */
	private func applyPanelColor(_ color: NSColor, as effect: TextFormatterEffectKind) {
		guard let editor else { return }

		let range = editor.field.selectedRange()
		if let colorDigit = NSColor.formatterColors.firstIndex(of: color) {
			editor.apply(effect, value: NSNumber(value: colorDigit), in: range)
		} else {
			editor.apply(effect, value: color, in: range)
		}
	}
}
