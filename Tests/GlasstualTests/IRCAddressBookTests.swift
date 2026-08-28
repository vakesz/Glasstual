@testable import Glasstual
import Testing

/** *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */
@MainActor
@Suite("Address book matching")
struct IRCAddressBookTests {
	@Test("A regular expression character in a hostmask matches itself")
	func ignoreEntryTreatsRegularExpressionCharactersLiterally() {
		let entry = AddressBookEntry
			.newIgnoreEntry(forHostmask: "nick[1]!*@example.com")

		#expect(entry.checkMatch("NICK[1]!user@example.com"))
		#expect(entry.checkMatch("nick1!user@example.com") == false)
		#expect(entry.hostmaskRegularExpression == #"^nick\[1]!.*?@example\.com$"#)
	}

	@Test("IRC wildcards are honoured and the match is anchored at both ends")
	func ignoreEntrySupportsIRCWildcardsAndAnchorsTheMatch() {
		let entry = AddressBookEntry
			.newIgnoreEntry(forHostmask: "n?ck!*@*.example")

		#expect(entry.checkMatch("nick!user@irc.example"))
		#expect(entry.checkMatch("prefix-nick!user@irc.example") == false)
		#expect(entry.checkMatch("noock!user@irc.example") == false)
	}

	@Test("A tracking entry takes its nickname from the hostmask and matches the whole mask")
	func userTrackingEntryDerivesNicknameAndMatchesFullHostmask() {
		var entry = AddressBookEntry.newUserTrackingEntry()

		entry.hostmask = "Alice"

		#expect(entry.trackingNickname == "Alice")
		#expect(entry.checkMatch("alice!user@example.com"))
		#expect(entry.checkMatch("alice") == false)
	}

	@Test("A mixed entry carries no matcher state at all")
	func mixedEntryHasNoMatcherState() {
		var entry = AddressBookEntry.newIgnoreEntry()

		entry.entryType = .mixed

		#expect(entry.hostmaskRegularExpression == "")
		#expect(entry.trackingNickname == nil)
		#expect(entry.checkMatch("") == false)
	}
}
