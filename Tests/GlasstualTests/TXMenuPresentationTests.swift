/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import AppKit
@testable import Glasstual
import XCTest

@MainActor
final class TXMenuPresentationTests: XCTestCase {
	func testSymbolPassPadsPlainItemsAndPreservesSubmenus() throws {
		let menu = NSMenu(title: "Root")
		let symbolItem = NSMenuItem(title: "Copy", action: nil, keyEquivalent: "")
		guard
			let rootSymbol = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: nil),
			let submenuSymbol = NSImage(
				systemSymbolName: "arrowshape.turn.up.left",
				accessibilityDescription: nil
			)
		else {
			throw XCTSkip("SF Symbols are unavailable in this test host")
		}
		symbolItem.image = rootSymbol
		let plainItem = NSMenuItem(title: "Paste", action: nil, keyEquivalent: "")
		let submenu = NSMenu(title: "Nested")
		let nestedSymbol = NSMenuItem(title: "Reply", action: nil, keyEquivalent: "")
		nestedSymbol.image = submenuSymbol
		let nestedPlain = NSMenuItem(title: "React", action: nil, keyEquivalent: "")

		submenu.addItem(nestedSymbol)
		submenu.addItem(nestedPlain)
		plainItem.submenu = submenu
		menu.addItem(symbolItem)
		menu.addItem(plainItem)

		MenuPresentation.apply(to: menu)

		XCTAssertNotNil(symbolItem.image)
		XCTAssertNotNil(plainItem.image)
		XCTAssertNotNil(nestedSymbol.image)
		XCTAssertNotNil(nestedPlain.image)
		XCTAssertFalse(try XCTUnwrap(plainItem.image).isTemplate)
	}

	func testReplyMenuRetainsResponderSelectorsAndContext() throws {
		let target = MenuTarget()
		let items = MenuPresentation.messageReplyItems(
			messageIdentifier: "message-42",
			nickname: "alice",
			excerpt: "Hello",
			target: target
		)

		XCTAssertEqual(items.count, 3)
		XCTAssertTrue(items[0].isSeparatorItem)
		XCTAssertEqual(items[1].action, #selector(MenuTarget.replyToMessage(_:)))
		XCTAssertTrue(items[1].target === target)
		XCTAssertEqual(
			(items[1].representedObject as? [String: String])?["messageIdentifier"],
			"message-42"
		)

		let reactionItems = try XCTUnwrap(items[2].submenu).items
		XCTAssertEqual(reactionItems.count, 8)
		XCTAssertEqual(reactionItems[0].action, #selector(MenuTarget.reactToMessage(_:)))
		XCTAssertEqual(
			(reactionItems[0].representedObject as? [String: String])?["emoji"],
			"👍"
		)
		XCTAssertEqual(
			reactionItems.last?.action,
			#selector(MenuTarget.reactToMessageWithOtherEmoji(_:))
		)
	}

	func testEmptyShareMenuItemKeepsMenuShape() {
		let item = MenuPresentation.shareMenuItem(for: [])

		XCTAssertFalse(item.isEnabled)
		XCTAssertNotNil(item.image)
	}

	func testMenuValidationRejectsCommandSpecificFailure() {
		XCTAssertFalse(
			MenuValidationPolicy.validate(
				tag: 100,
				commandSpecificResult: false,
				applicationIsLaunched: true,
				mainWindowHasAttachedSheet: false,
				mainWindowIsFocused: true,
				mainWindowIsBeneathMouse: false
			)
		)
	}

	func testTopLevelMenusRemainAvailableDuringLaunch() {
		for tag in 1 ... 10 {
			XCTAssertTrue(
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

	func testSheetPolicyAllowsSettingsButDisablesChannelActions() {
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

		XCTAssertTrue(validate(102))
		XCTAssertTrue(validate(200))
		XCTAssertFalse(validate(600))
	}

	func testEssentialCommandsRemainAvailableBeforeLaunch() {
		for tag in [100, 113, 203, 205, 305, 812, 900, 910, 912, 9_100_004] {
			XCTAssertTrue(
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
