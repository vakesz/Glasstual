// Copyright (c) 2010 - 2018 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing

@MainActor
@Suite("Address book match cache")
struct AddressBookMatchCacheTests {
	@Test("One matching entry is returned with the flags it was configured with")
	func singleMatchingEntryIsReturned() throws {
		let session = makeSession(ignoreList: [[
			"entryType": AddressBookEntryKind.ignore.rawValue as NSNumber,
			"hostmask": "nick!*@example.com" as NSString,
			"ignorePrivateMessages": true as NSNumber,
		]])
		let cache = AddressBookMatchCache()
		let match = try #require(cache.findAddressBookEntry(forHostmask: "Nick!user@example.com", in: session.config.ignoreList))

		#expect(match.entryType == .ignore)
		#expect(match.ignorePrivateMessages)
		#expect(cache.findIgnores(forHostmask: "Nick!user@example.com", in: session.config.ignoreList).count == 1)
	}

	@Test("Entries that match the same hostmask are merged into one mixed entry")
	func multipleMatchesAreMerged() throws {
		let session = makeSession(ignoreList: [
			[
				"entryType": AddressBookEntryKind.ignore.rawValue as NSNumber,
				"hostmask": "*!user@example.com" as NSString,
				"ignorePrivateMessages": true as NSNumber,
			],
			[
				"entryType": AddressBookEntryKind.ignore.rawValue as NSNumber,
				"hostmask": "nick!*@example.com" as NSString,
				"ignorePublicMessages": true as NSNumber,
			],
		])
		let cache = AddressBookMatchCache()
		let hostmask = "nick!user@example.com"
		let match = try #require(cache.findAddressBookEntry(forHostmask: hostmask, in: session.config.ignoreList))

		#expect(match.entryType == .mixed)
		#expect(match.parentEntries?.count == 2)
		#expect(match.ignorePrivateMessages)
		#expect(match.ignorePublicMessages)
		#expect(cache.findIgnores(forHostmask: hostmask, in: session.config.ignoreList).count == 2)
		#expect(match == cache.findAddressBookEntry(forHostmask: hostmask, in: session.config.ignoreList))
	}

	@Test("A hostmask nothing matches yields no entry and no ignores")
	func absentMatchReturnsNilAndNoIgnores() {
		let session = makeSession(ignoreList: [[
			"entryType": AddressBookEntryKind.ignore.rawValue as NSNumber,
			"hostmask": "nick!*@example.com" as NSString,
		]])
		let cache = AddressBookMatchCache()
		let hostmask = "someone!user@elsewhere.test"

		#expect(cache.findAddressBookEntry(forHostmask: hostmask, in: session.config.ignoreList) == nil)
		#expect(cache.findIgnores(forHostmask: hostmask, in: session.config.ignoreList).isEmpty)

		cache.clearCachedMatches(forHostmask: hostmask)
		cache.clearCachedMatches()
	}

	/// The cache holds its session weakly, so every test keeps the session it
	/// was built from alive for the length of the test.
	private func makeSession(ignoreList: [[String: AnyObject]]) -> TestServerSession {
		TestServerSession(configDictionary: ["ignoreList": ignoreList])
	}
}
