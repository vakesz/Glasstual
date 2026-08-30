/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import AppKit
@testable import Glasstual
import Testing

/// A headless AppKit host can be built without the SF Symbols catalogue, and
/// can decline to hold a symbol image on a menu item. The symbol pass has
/// nothing to place on such a host, so the tests that check it are skipped.
private nonisolated func menuSymbolImagesAreAvailable() -> Bool {
	guard
		let symbol = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: nil),
		NSImage(systemSymbolName: "arrowshape.turn.up.left", accessibilityDescription: nil) != nil
	else {
		return false
	}

	let item = NSMenuItem(title: "Copy", action: nil, keyEquivalent: "")
	item.image = symbol

	return item.image != nil
}

@MainActor
@Suite("Menu presentation")
struct TXMenuPresentationTests {
	@Test("Every symbol a menu command names resolves in the system catalogue")
	func mainMenuSymbolMappingsResolveThroughSystemCatalog() {
		let mappings = MenuPresentation.symbolMappings

		#expect(MenuCommand.settings.symbolName == "gear")
		#expect(MenuCommand.findText.symbolName == "magnifyingglass")
		#expect(MenuPresentation.symbolName(forTag: -1) == nil)

		let unavailableSymbols = mappings.values.filter {
			NSImage(systemSymbolName: $0, accessibilityDescription: $0) == nil
		}

		#expect(unavailableSymbols.isEmpty, "Unavailable symbols: \(unavailableSymbols.sorted())")
	}

	@Test("The symbol pass adds an image without touching the item's title, tag or key equivalent")
	func symbolPassAssignsMappedImageWithoutChangingMenuIdentity() {
		let menu = NSMenu(title: "Application")
		let item = NSMenuItem(title: "Settings…", action: nil, keyEquivalent: ",")
		item.tag = 102
		menu.addItem(item)

		MenuPresentation.apply(to: menu)

		#expect(item.title == "Settings…")
		#expect(item.tag == 102)
		#expect(item.keyEquivalent == ",")
		#expect(item.image != nil)
	}

	@Test(
		"An item with no symbol is padded to align with its neighbours, submenus included",
		.enabled(if: menuSymbolImagesAreAvailable(), "SF Symbols are unavailable in this test host")
	)
	func symbolPassPadsPlainItemsAndPreservesSubmenus() throws {
		let menu = NSMenu(title: "Root")
		let symbolItem = NSMenuItem(title: "Copy", action: nil, keyEquivalent: "")
		symbolItem.image = try #require(NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: nil))
		let plainItem = NSMenuItem(title: "Paste", action: nil, keyEquivalent: "")
		let submenu = NSMenu(title: "Nested")
		let nestedSymbol = NSMenuItem(title: "Reply", action: nil, keyEquivalent: "")
		nestedSymbol.image = try #require(NSImage(
			systemSymbolName: "arrowshape.turn.up.left",
			accessibilityDescription: nil
		))
		let nestedPlain = NSMenuItem(title: "React", action: nil, keyEquivalent: "")

		submenu.addItem(nestedSymbol)
		submenu.addItem(nestedPlain)
		plainItem.submenu = submenu
		menu.addItem(symbolItem)
		menu.addItem(plainItem)

		MenuPresentation.apply(to: menu)

		#expect(symbolItem.image != nil)
		#expect(plainItem.image != nil)
		#expect(nestedSymbol.image != nil)
		#expect(nestedPlain.image != nil)

		let paddingImage = try #require(plainItem.image)

		#expect(paddingImage.isTemplate == false)
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

	@Test("A command that vetoes itself is disabled whatever the window state is")
	func menuValidationRejectsCommandSpecificFailure() {
		#expect(
			MenuValidationPolicy.validate(
				tag: 100,
				commandSpecificResult: false,
				applicationIsLaunched: true,
				mainWindowHasAttachedSheet: false,
				mainWindowIsFocused: true,
				mainWindowIsBeneathMouse: false
			) == false
		)
	}

	@Test("The top level menu titles stay available while the application is still launching")
	func topLevelMenusRemainAvailableDuringLaunch() {
		for tag in 1 ... 10 {
			#expect(
				MenuValidationPolicy.validate(
					tag: tag,
					commandSpecificResult: true,
					applicationIsLaunched: false,
					mainWindowHasAttachedSheet: true,
					mainWindowIsFocused: false,
					mainWindowIsBeneathMouse: false
				)
			)
		}
	}

	@Test("A sheet leaves Settings reachable but disables the channel commands behind it")
	func sheetPolicyAllowsSettingsButDisablesChannelActions() {
		let validate: (Int) -> Bool = { tag in
			MenuValidationPolicy.validate(
				tag: tag,
				commandSpecificResult: true,
				applicationIsLaunched: true,
				mainWindowHasAttachedSheet: true,
				mainWindowIsFocused: true,
				mainWindowIsBeneathMouse: false
			)
		}

		#expect(validate(102))
		#expect(validate(200))
		#expect(validate(600) == false)
	}

	@Test("The commands a user needs before the application has launched stay enabled")
	func essentialCommandsRemainAvailableBeforeLaunch() {
		for tag in [100, 113, 203, 205, 305, 812, 900, 910, 912, 9_100_004] {
			#expect(
				MenuValidationPolicy.validate(
					tag: tag,
					commandSpecificResult: true,
					applicationIsLaunched: false,
					mainWindowHasAttachedSheet: false,
					mainWindowIsFocused: true,
					mainWindowIsBeneathMouse: false
				)
			)
		}
	}
}

@MainActor
private final class MenuTarget: NSObject {
	@objc func replyToMessage(_: Any?) {}
	@objc func reactToMessage(_: Any?) {}
	@objc func reactToMessageWithOtherEmoji(_: Any?) {}
}
