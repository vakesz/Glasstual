// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit

/** The system Fonts panel, while Settings has it choosing the transcript font.

 The panel and its font manager are shared by the whole application. While a
 presentation of ours is up the manager sends `changeFont(_:)` here; once the
 panel closes, or Settings closes, the target is handed back so a later font
 change goes to the first responder again. */
@MainActor
final class TranscriptFontPanel: NSObject, NSFontChanging {
	/// Where each chosen font goes, while a presentation of ours is up.
	private var fontChanged: ((NSFont) -> Void)?
	/// The font the panel was last told about, which is what the manager
	/// converts when the reader picks a family, face or size.
	private var currentFont: NSFont?
	/// Which presentation is current: the close notification arrives a turn
	/// late, after the panel may have been opened again.
	private var presentation = 0
	private let notifications = NotificationSubscriptions()

	/// Opens the Fonts panel on `font` and reports every font the reader picks
	/// until the panel closes or ``release()`` is called.
	func present(selecting font: NSFont, fontChanged: @escaping (NSFont) -> Void) {
		self.fontChanged = fontChanged
		currentFont = font

		let manager = NSFontManager.shared
		manager.target = self
		manager.action = #selector(changeFont(_:))
		manager.setSelectedFont(font, isMultiple: false)

		presentation += 1
		let presentation = presentation
		let panel = manager.fontPanel(true)

		notifications.cancelAll()
		notifications.observe(NSWindow.willCloseNotification, object: panel) { [weak self] _ in
			guard let self, presentation == self.presentation else { return }
			release()
		}

		manager.orderFrontFontPanel(self)
	}

	/// Stops answering the panel and hands the font manager back.
	func release() {
		notifications.cancelAll()
		fontChanged = nil
		currentFont = nil
		let manager = NSFontManager.shared
		if manager.target === self {
			manager.target = nil
			manager.action = #selector(NSFontChanging.changeFont(_:))
		}
	}

	func changeFont(_ sender: NSFontManager?) {
		guard let sender, let currentFont, let fontChanged else { return }
		let font = sender.convert(currentFont)
		self.currentFont = font
		fontChanged(font)
	}

	/// The transcript draws one font at one size: underline, colour and shadow
	/// belong to the theme, not to the font.
	func validModesForFontPanel(_: NSFontPanel) -> NSFontPanel.ModeMask {
		[.collection, .face, .size]
	}
}

/** What the transcript theme stores for a font picked in the Fonts panel.

 The panel offers sizes the renderer refuses, so the size is held to the
 theme's own bounds rather than having the whole theme rejected. The system
 font keeps the name the theme has always stored for it, which is what makes
 the Style pane call it the system font. */
struct TranscriptFontChoice: Equatable {
	let name: String
	let size: CGFloat

	init(name: String, size: CGFloat) {
		self.name = name
		let range = TranscriptTheme.fontSizeRange
		self.size = min(max(size, range.lowerBound), range.upperBound)
	}

	init(_ font: NSFont) {
		self.init(name: font.fontName, size: font.pointSize)
	}

	/// What the Style pane calls the font a theme names.
	static func displayName(for fontName: String) -> String {
		if fontName == TranscriptTheme.lines.fontName {
			return String(localized: .Settings.styleFontSystem)
		}
		return NSFont(name: fontName, size: NSFont.systemFontSize)?.displayName ?? fontName
	}
}
