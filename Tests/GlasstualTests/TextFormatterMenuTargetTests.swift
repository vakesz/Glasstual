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
	private func makeWindow() -> (window: NSWindow, field: TextViewWithIRCFormatter) {
		let window = NSWindow(
			contentRect: NSRect(x: 0, y: 0, width: 320, height: 120),
			styleMask: [.titled],
			backing: .buffered,
			defer: false
		)
		let field = TextViewWithIRCFormatter(frame: NSRect(x: 0, y: 0, width: 320, height: 40))
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
		let menu = TextViewIRCFormattingMenu()
		let (window, _) = makeWindow()

		#expect(NSApp.keyWindow !== window)
		#expect(menu.validateMenuItem(boldItem()) == false)
	}

	@Test("The attached window's first responder is the target, key or not")
	func attachedWindowSuppliesTheTarget() {
		let menu = TextViewIRCFormattingMenu()
		let (window, _) = makeWindow()
		menu.attach(to: window)

		#expect(NSApp.keyWindow !== window)
		#expect(menu.validateMenuItem(boldItem()))
	}

	@Test("A window whose responder is not a formatting field is no target")
	func nonFormattingResponderIsNoTarget() {
		let menu = TextViewIRCFormattingMenu()
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
}
