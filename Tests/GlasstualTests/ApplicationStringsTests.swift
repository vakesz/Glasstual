/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

@testable import Glasstual
import XCTest

@MainActor
final class ApplicationStringsTests: XCTestCase {
	func testSemanticAccessorsResolveBasicLanguageCatalog() {
		XCTAssertEqual(ApplicationStrings.unknownValue, "Unknown")
		XCTAssertEqual(
			ApplicationStrings.defaultQuitMessage,
			"Glasstual IRC Client: https://github.com/vakesz/Glasstual"
		)
		XCTAssertEqual(ApplicationStrings.untitledConnection, "Untitled Connection")
		XCTAssertEqual(ApplicationStrings.sleepQuitMessage, "My Mac has gone to sleep. ZZZzzz…")
		XCTAssertEqual(ApplicationStrings.closeQuery, "Close Query")
		XCTAssertEqual(ApplicationStrings.closeWindow, "Close Window")
		XCTAssertEqual(ApplicationStrings.leaveChannel, "Leave Channel")
		XCTAssertEqual(ApplicationStrings.quitApplication, "Quit Glasstual")
		XCTAssertEqual(ApplicationStrings.disconnect(from: "Libera.Chat"), "Disconnect from Libera.Chat")
		XCTAssertEqual(ApplicationStrings.copyLogAsHTML, "Copy Log as HTML")
		XCTAssertEqual(ApplicationStrings.forceReloadStyle, "Force Reload Style")
		XCTAssertEqual(ApplicationStrings.openWebInspector, "Open Web Inspector")
		XCTAssertEqual(ApplicationStrings.lookUpInDictionary, "Look Up in Dictionary")
		XCTAssertEqual(ApplicationStrings.lookUpInDictionary("Swift"), "Look Up “Swift”")
		XCTAssertEqual(ApplicationStrings.search(with: "DuckDuckGo"), "Search With DuckDuckGo")
		XCTAssertEqual(ApplicationStrings.noActionsAvailable, "No Actions Available")
		XCTAssertEqual(ApplicationStrings.builtInTheme, "Built-in")
		XCTAssertEqual(ApplicationStrings.customTheme, "Custom")
		XCTAssertEqual(ApplicationStrings.requiredField, "Fill out this field")
		XCTAssertEqual(ApplicationStrings.ircColors, "IRC Colors")
		XCTAssertEqual(ApplicationStrings.ircColor(at: 7), "Color 7")
		XCTAssertEqual(ApplicationStrings.relativeTime("5 minutes"), "5 minutes ago")
	}
}
