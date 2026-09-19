// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation
@testable import Glasstual
import Testing

/// Only the settings an entry's type uses are read or written, so an ignore
/// rule carries nothing about user tracking and the other way round.
@Suite("Address-book entry property-list round trip")
struct AddressBookCodableTests {
	@Test("A stored ignore entry re-encodes unchanged")
	func roundTripsAStoredIgnoreEntry() throws {
		// Captured from the class-based `AddressBookEntry.dictionaryValue`,
		// which already dropped the settings left at their default.
		let fixture: [String: PropertyListValue] = [
			"hostmask": "spammer!*@example.test",
			"uniqueIdentifier": "8B2F4C1A-0000-4000-8000-000000000004",
			"ignoreClientToClientProtocol": true,
			"ignorePublicMessages": true,
		]

		let entry = try #require(PropertyListModel.decode(AddressBookEntry.self, from: fixture))

		#expect(entry.entryType == .ignore)
		#expect(PropertyListModel.encode(entry) == fixture)
	}

	@Test("A user-tracking entry writes its type and only its own setting")
	func roundTripsAStoredTrackingEntry() throws {
		let fixture: [String: PropertyListValue] = [
			"hostmask": "alice",
			"uniqueIdentifier": "8B2F4C1A-0000-4000-8000-000000000005",
			"trackUserActivity": true,
			"entryType": 1,
		]

		let entry = try #require(PropertyListModel.decode(AddressBookEntry.self, from: fixture))

		#expect(entry.entryType == .userTracking)
		#expect(entry.trackUserActivity)
		#expect(PropertyListModel.encode(entry) == fixture)
	}

	/// A field nothing declares is not a setting: it decodes to nothing and is
	/// not written back.
	@Test("A key this build does not know leaves the entry on its defaults")
	func unknownKeysAreIgnored() throws {
		let entry = try #require(PropertyListModel.decode(AddressBookEntry.self, from: [
			"hostmask": "spammer!*@example.test",
			"ignoreCTCP": true,
			"ignorePublicMsg": true,
		]))

		#expect(entry.ignoreClientToClientProtocol == false)
		#expect(entry.ignorePublicMessages == false)
		#expect(PropertyListModel.encode(entry) == ["hostmask": "spammer!*@example.test",
		                                            "uniqueIdentifier": .string(entry.uniqueIdentifier)])
	}

	@Test("Editing the hostmask recompiles the matcher")
	func editingTheHostmaskRebuildsTheMatcher() {
		var entry = AddressBookEntry.newIgnoreEntry(forHostmask: "alice!*@example.test")

		#expect(entry.checkMatch("alice!user@example.test"))

		entry.hostmask = "bob!*@example.test"

		#expect(entry.checkMatch("alice!user@example.test") == false)
		#expect(entry.checkMatch("bob!user@example.test"))
	}
}
