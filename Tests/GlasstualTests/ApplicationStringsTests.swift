/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

@testable import Glasstual
import Testing

@MainActor
@Suite("Application strings")
struct ApplicationStringsTests {
	/// The catalogue's own text is not the contract; where its placeholder lands
	/// is, because the generated accessor is what puts it there.
	@Test("A generated accessor drops its argument where the catalogue's placeholder sits")
	func catalogAccessorsPlaceTheirArguments() {
		#expect(ApplicationStrings.disconnect(from: "Libera.Chat") == "Disconnect from Libera.Chat")
		#expect(ApplicationStrings.lookUpInDictionary("Swift") == "Look Up “Swift”")
		#expect(ApplicationStrings.search(with: "DuckDuckGo") == "Search With DuckDuckGo")
		#expect(ApplicationStrings.ircColor(at: 7) == "Color 7")
		#expect(ApplicationStrings.relativeTime("5 minutes") == "5 minutes ago")
	}
}
