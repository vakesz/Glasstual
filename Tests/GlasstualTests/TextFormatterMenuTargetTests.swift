/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import AppKit
@testable import Glasstual
import Testing

/** The formatting menu used to find its text field through
 `NSApp.keyWindow?.firstResponder`. `NSColorPanel` becomes key the moment it is
 clicked, so every colour the panel reported went nowhere and the custom-colour
 items did nothing. A window keeps its own first responder whether or not it is
 key, which is why the menu asks the window it belongs to.

 Nothing is key in a test host, so an unattached menu reproduces exactly the
 state the bug put the menu in. */
@Suite("Formatting menu target")
@MainActor
struct TextFormatterMenuTargetTests {
	private func makeWindow() -> (window: NSWindow, field: IRCFormattedTextView) {
		let window = NSWindow(
			contentRect: NSRect(x: 0, y: 0, width: 320, height: 120),
			styleMask: [.titled],
			backing: .buffered,
			defer: false
		)
		let field = IRCFormattedTextView(frame: NSRect(x: 0, y: 0, width: 320, height: 40))
		field.isEditable = true
		window.contentView?.addSubview(field)
		window.makeFirstResponder(field)
		return (window, field)
	}

	private func boldItem() -> NSMenuItem {
		let item = NSMenuItem(title: "Bold", action: nil, keyEquivalent: "")
		item.tag = TextFormatterCommand.bold.rawValue
		return item
	}

	@Test("An unattached menu finds nothing while no window is key")
	func unattachedMenuFindsNothing() {
		let menu = IRCFormattingMenu()
		let (window, _) = makeWindow()

		#expect(NSApp.keyWindow !== window)
		#expect(menu.validateMenuItem(boldItem()) == false)
	}

	/** The IRC palette used to be attached to `NSColorPanel.shared` while the
	 main window was still installing this menu. Asking for the shared panel
	 builds the whole system picker, and its colour wheel draws through
	 CoreImage, so a launch loaded Metal and its shader caches for a picker most
	 sessions never open. The palette is attached from the presentation instead.

	 The shared panel is process-wide, so what is pinned is that installing the
	 menu does not change whether it exists — not that it never does. */
	@Test("Installing the formatting menu does not build the shared colour panel")
	func installingTheMenuLeavesTheColorPanelUnbuilt() {
		let existedBefore = NSColorPanel.sharedColorPanelExists
		let menu = IRCFormattingMenu()
		let (window, _) = makeWindow()
		menu.attach(to: window)
		_ = menu.makeMenu()

		#expect(NSColorPanel.sharedColorPanelExists == existedBefore)
	}

	@Test("The attached window's first responder is the target, key or not")
	func attachedWindowSuppliesTheTarget() {
		let menu = IRCFormattingMenu()
		let (window, _) = makeWindow()
		menu.attach(to: window)

		#expect(NSApp.keyWindow !== window)
		#expect(menu.validateMenuItem(boldItem()))
	}

	@Test("A window whose responder is not a formatting field is no target")
	func nonFormattingResponderIsNoTarget() {
		let menu = IRCFormattingMenu()
		let window = NSWindow(
			contentRect: NSRect(x: 0, y: 0, width: 320, height: 120),
			styleMask: [.titled],
			backing: .buffered,
			defer: false
		)
		let searchField = NSSearchField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
		window.contentView?.addSubview(searchField)
		window.makeFirstResponder(searchField)
		menu.attach(to: window)

		#expect(menu.validateMenuItem(boldItem()) == false)
	}

	/// Each colour item's title is only a number. VoiceOver had nothing else to
	/// read, so a reader who could not see the swatch could not pick a colour.
	@Test("Every palette colour names itself to VoiceOver")
	func paletteColoursCarryTheirNames() throws {
		let menu = IRCFormattingMenu()

		for palette in try [#require(menu.foregroundColorMenu), #require(menu.backgroundColorMenu)] {
			let colourItems = palette.items.filter {
				$0.isSeparatorItem == false && NSColor.formatterColors.indices.contains($0.tag)
			}
			#expect(colourItems.count == NSColor.formatterColors.count)
			for item in colourItems {
				let name = try #require(item.accessibilityValue() as? String)
				#expect(name.isEmpty == false)
				#expect(item.image?.accessibilityDescription == name)
			}
		}
	}
}
