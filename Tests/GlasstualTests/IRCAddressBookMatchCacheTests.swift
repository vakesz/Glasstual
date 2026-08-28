/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2010 - 2018 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 *
 *  * Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 *  * Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 *  * Neither the name of Textual, "Codeux Software, LLC", nor the
 *    names of its contributors may be used to endorse or promote products
 *    derived from this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED. IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
 * FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
 * OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
 * LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
 * OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
 * SUCH DAMAGE.
 *
 *********************************************************************** */

import Foundation
@testable import Glasstual
import Testing

@MainActor
@Suite("Address book match cache")
struct IRCAddressBookMatchCacheTests {
	@Test("One matching entry is returned with the flags it was configured with")
	func singleMatchingEntryIsReturned() throws {
		let client = makeClient(ignoreList: [[
			"entryType": IRCAddressBookEntryType.ignore.rawValue as NSNumber,
			"hostmask": "nick!*@example.com" as NSString,
			"ignorePrivateMessages": true as NSNumber,
		]])
		let cache = IRCAddressBookMatchCache(client: client)
		let match = try #require(cache.findAddressBookEntry(forHostmask: "Nick!user@example.com"))

		#expect(match.entryType == .ignore)
		#expect(match.ignorePrivateMessages)
		#expect(cache.findIgnores(forHostmask: "Nick!user@example.com").count == 1)
	}

	@Test("Entries that match the same hostmask are merged into one mixed entry")
	func multipleMatchesAreMerged() throws {
		let client = makeClient(ignoreList: [
			[
				"entryType": IRCAddressBookEntryType.ignore.rawValue as NSNumber,
				"hostmask": "*!user@example.com" as NSString,
				"ignorePrivateMessages": true as NSNumber,
			],
			[
				"entryType": IRCAddressBookEntryType.ignore.rawValue as NSNumber,
				"hostmask": "nick!*@example.com" as NSString,
				"ignorePublicMessages": true as NSNumber,
			],
		])
		let cache = IRCAddressBookMatchCache(client: client)
		let hostmask = "nick!user@example.com"
		let match = try #require(cache.findAddressBookEntry(forHostmask: hostmask))

		#expect(match.entryType == .mixed)
		#expect(match.parentEntries?.count == 2)
		#expect(match.ignorePrivateMessages)
		#expect(match.ignorePublicMessages)
		#expect(cache.findIgnores(forHostmask: hostmask).count == 2)
		#expect(match == cache.findAddressBookEntry(forHostmask: hostmask))
	}

	@Test("A hostmask nothing matches yields no entry and no ignores")
	func absentMatchReturnsNilAndNoIgnores() {
		let client = makeClient(ignoreList: [[
			"entryType": IRCAddressBookEntryType.ignore.rawValue as NSNumber,
			"hostmask": "nick!*@example.com" as NSString,
		]])
		let cache = IRCAddressBookMatchCache(client: client)
		let hostmask = "someone!user@elsewhere.test"

		#expect(cache.findAddressBookEntry(forHostmask: hostmask) == nil)
		#expect(cache.findIgnores(forHostmask: hostmask).isEmpty)

		cache.clearCachedMatches(forHostmask: hostmask)
		cache.clearCachedMatches()
	}

	/// The cache holds its client weakly, so every test keeps the client it
	/// was built from alive for the length of the test.
	private func makeClient(ignoreList: [[String: AnyObject]]) -> GLTTestClient {
		GLTTestClient(configDictionary: ["ignoreList": ignoreList])
	}
}
