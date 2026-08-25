import Glasstual
import XCTest

/** *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */
class IRCAddressBookTests: XCTestCase {
	func testIgnoreEntryTreatsRegularExpressionCharactersLiterally() {
		let entry = IRCAddressBookEntry
			.newIgnore(forHostmask: "nick[1]!*@example.com")

		XCTAssertTrue(entry.checkMatch("NICK[1]!user@example.com"))
		XCTAssertFalse(entry.checkMatch("nick1!user@example.com"))
		XCTAssertEqual(entry.hostmaskRegularExpression, #"^nick\[1]!.*?@example\.com$"#)
	}

	func testIgnoreEntrySupportsIRCWildcardsAndAnchorsTheMatch() {
		let entry = IRCAddressBookEntry
			.newIgnore(forHostmask: "n?ck!*@*.example")

		XCTAssertTrue(entry.checkMatch("nick!user@irc.example"))
		XCTAssertFalse(entry.checkMatch("prefix-nick!user@irc.example"))
		XCTAssertFalse(entry.checkMatch("noock!user@irc.example"))
	}

	func testUserTrackingEntryDerivesNicknameAndMatchesFullHostmask() {
		let entry = IRCAddressBookEntryMutable.newUserTracking()

		entry.hostmask = "Alice"

		XCTAssertEqual(entry.trackingNickname, "Alice")

		XCTAssertTrue(entry.checkMatch("alice!user@example.com"))

		XCTAssertFalse(entry.checkMatch("alice"))
	}

	func testMixedEntryHasNoMatcherState() {
		let entry = IRCAddressBookEntryMutable.newIgnore()

		entry.entryType = .mixed

		XCTAssertEqual(entry.hostmaskRegularExpression, "")

		XCTAssertNil(entry.trackingNickname)

		XCTAssertFalse(entry.checkMatch(""))
	}
}
