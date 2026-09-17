// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
@testable import Glasstual
import Testing

@MainActor
@Suite("Menu presentation")
struct MenuPresentationTests {
	/// That every mapped symbol exists in the system catalogue is stated once,
	/// in `MenuCommandTests.symbolNamesResolve`; what this adds is that the
	/// symbols belong to the contextual menus and to nothing else.
	@Test("Only the commands contextual menus carry take a symbol")
	func symbolsBelongToContextualMenusOnly() {
		#expect(MenuCommand.connect.symbolName == "bolt")
		#expect(MenuCommand.whois.symbolName == "info.circle")
		/* The menu bar draws no images: macOS draws none beside its own
		 commands, and a column of symbols next to Cut, Copy and Quit reads as
		 decoration. */
		#expect(MenuCommand.settings.symbolName == nil)
		#expect(MenuCommand.quit.symbolName == nil)
		#expect(MenuCommand.selectAll.symbolName == nil)
		#expect(MenuCommand.zoom.symbolName == nil)
	}

	@Test("The symbol pass adds an image without touching the item's command or key equivalent")
	func symbolPassAssignsMappedImageWithoutChangingMenuIdentity() {
		let menu = NSMenu(title: "Server")
		let item = NSMenuItem(title: "Connect", action: nil, keyEquivalent: "k")
		item.command = .connect
		menu.addItem(item)

		MenuPresentation.apply(to: menu)

		#expect(item.title == "Connect")
		#expect(item.command == .connect)
		#expect(item.keyEquivalent == "k")
		#expect(item.image != nil)
	}

	/// The transparent "circle" spacer that used to pad unmapped items is gone
	/// with the menu-bar symbols it existed for.
	@Test("An item with no symbol is left without an image, submenus included")
	func symbolPassLeavesUnmappedItemsPlain() {
		let menu = NSMenu(title: "Root")
		let symbolItem = NSMenuItem(title: "Connect", action: nil, keyEquivalent: "")
		symbolItem.command = .connect
		let plainItem = NSMenuItem(title: "Nested", action: nil, keyEquivalent: "")
		let submenu = NSMenu(title: "Nested")
		let nestedSymbol = NSMenuItem(title: "Get Info", action: nil, keyEquivalent: "")
		nestedSymbol.command = .whois
		let nestedPlain = NSMenuItem(title: "Plain", action: nil, keyEquivalent: "")

		submenu.addItem(nestedSymbol)
		submenu.addItem(nestedPlain)
		plainItem.submenu = submenu
		menu.addItem(symbolItem)
		menu.addItem(plainItem)

		MenuPresentation.apply(to: menu)

		#expect(symbolItem.image != nil)
		#expect(plainItem.image == nil)
		#expect(nestedSymbol.image != nil)
		#expect(nestedPlain.image == nil)
	}

	@Test("A reply menu carries the responder selectors and the message it was built for")
	func replyMenuRetainsResponderSelectorsAndContext() throws {
		let target = MenuTarget()
		let items = MenuPresentation.messageReplyItems(
			messageIdentifier: "message-42",
			nickname: "alice",
			excerpt: "Hello",
			target: target
		)

		#expect(items.count == 3)
		#expect(items[0].isSeparatorItem)
		#expect(items[1].action == #selector(MenuTarget.replyToMessage(_:)))
		#expect(items[1].target === target)
		#expect((items[1].representedObject as? MessageMenuContext)?.messageIdentifier == "message-42")

		let reactionItems = try #require(items[2].submenu).items

		#expect(reactionItems.count == 8)
		#expect(reactionItems[0].action == #selector(MenuTarget.reactToMessage(_:)))
		#expect((reactionItems[0].representedObject as? MessageMenuContext)?.emoji == "👍")
		#expect(reactionItems.last?.action == #selector(MenuTarget.reactToMessageWithOtherEmoji(_:)))
	}

	@Test("A share menu with nothing to share is present but disabled")
	func emptyShareMenuItemKeepsMenuShape() {
		let item = MenuPresentation.shareMenuItem(for: [])

		#expect(item.isEnabled == false)
		#expect(item.image != nil)
	}
}

@MainActor
private final class MenuTarget: NSObject {
	@objc func replyToMessage(_: Any?) {}
	@objc func reactToMessage(_: Any?) {}
	@objc func reactToMessageWithOtherEmoji(_: Any?) {}
}
