/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

@testable import Glasstual
import XCTest

@MainActor
final class ApplicationStringsTests: XCTestCase {
	/// The catalogue's own text is not the contract; where its placeholder lands
	/// is, because the generated accessor is what puts it there.
	func testCatalogAccessorsPlaceTheirArguments() {
		XCTAssertEqual(ApplicationStrings.disconnect(from: "Libera.Chat"), "Disconnect from Libera.Chat")
		XCTAssertEqual(ApplicationStrings.lookUpInDictionary("Swift"), "Look Up “Swift”")
		XCTAssertEqual(ApplicationStrings.search(with: "DuckDuckGo"), "Search With DuckDuckGo")
		XCTAssertEqual(ApplicationStrings.ircColor(at: 7), "Color 7")
		XCTAssertEqual(ApplicationStrings.relativeTime("5 minutes"), "5 minutes ago")
	}
}
