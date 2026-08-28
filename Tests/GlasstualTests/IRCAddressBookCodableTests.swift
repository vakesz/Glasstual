/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import CocoaExtensions
import Foundation
@testable import Glasstual
import Testing

/// Address-book entries have been spelled three different ways over the
/// years, and only the settings an entry's type uses are written out.
@Suite("Address-book entry property-list round trip")
struct IRCAddressBookCodableTests {
	@Test("A dictionary written by the previous release re-encodes unchanged")
	func roundTripsAStoredIgnoreEntry() throws {
		// Captured from the class-based `AddressBookEntry.dictionaryValue`,
		// which already dropped the settings left at their default.
		let fixture: [String: Any] = [
			"hostmask": "spammer!*@example.test",
			"uniqueIdentifier": "8B2F4C1A-0000-4000-8000-000000000004",
			"ignoreClientToClientProtocol": true,
			"ignorePublicMessages": true,
		]

		let entry = try #require(PropertyListModel.decode(AddressBookEntry.self, from: fixture))

		#expect(entry.entryType == .ignore)
		#expect(NSDictionary(dictionary: PropertyListModel.encode(entry)) == NSDictionary(dictionary: fixture))
	}

	@Test("A user-tracking entry writes its type and only its own setting")
	func roundTripsAStoredTrackingEntry() throws {
		let fixture: [String: Any] = [
			"hostmask": "alice",
			"uniqueIdentifier": "8B2F4C1A-0000-4000-8000-000000000005",
			"trackUserActivity": true,
			"entryType": 1,
		]

		let entry = try #require(PropertyListModel.decode(AddressBookEntry.self, from: fixture))

		#expect(entry.entryType == .userTracking)
		#expect(entry.trackUserActivity)
		#expect(NSDictionary(dictionary: PropertyListModel.encode(entry)) == NSDictionary(dictionary: fixture))
	}

	@Test(
		"Each legacy spelling still sets the setting it was renamed to",
		arguments: [
			("ignoreCTCP", "ignoreClientToClientProtocol"),
			("ignoreJPQE", "ignoreGeneralEventMessages"),
			("ignoreNotices", "ignoreNoticeMessages"),
			("ignorePMHighlights", "ignorePrivateMessageHighlights"),
			("ignorePrivateMsg", "ignorePrivateMessages"),
			("ignoreHighlights", "ignorePublicMessageHighlights"),
			("ignorePublicMsg", "ignorePublicMessages"),
		]
	)
	func legacyIgnoreAliases(legacyKey: String, canonicalKey: String) throws {
		let entry = try #require(PropertyListModel.decode(AddressBookEntry.self, from: [
			"hostmask": "spammer!*@example.test",
			legacyKey: true,
		]))

		// The alias landed on the same setting the canonical key writes.
		#expect(PropertyListModel.encode(entry)[canonicalKey] as? Bool == true)
	}

	@Test("notifyJoins still turns on user tracking")
	func legacyTrackingAlias() throws {
		let entry = try #require(PropertyListModel.decode(AddressBookEntry.self, from: [
			"entryType": 1,
			"hostmask": "alice",
			"notifyJoins": true,
		]))

		#expect(entry.trackUserActivity)
	}

	@Test("The canonical key wins when a legacy alias contradicts it")
	func canonicalKeyWinsOverAlias() throws {
		let entry = try #require(PropertyListModel.decode(AddressBookEntry.self, from: [
			"hostmask": "spammer!*@example.test",
			"ignoreClientToClientProtocol": false,
			"ignoreCTCP": true,
		]))

		#expect(entry.ignoreClientToClientProtocol == false)
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
