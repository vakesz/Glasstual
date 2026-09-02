/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
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
import GlasstualPluginKit
import Testing

/// One RFC 1459 §2.2 case pair: a mask, and the two spellings it has to match.
nonisolated struct IRCSpecCaseFoldPair: CustomTestStringConvertible { // nonisolated: value
	let mask: String
	let upper: String
	let lower: String

	var testDescription: String {
		"\(upper) == \(lower)"
	}
}

/// Case folding of the things IRC treats as names.
///
/// RFC 1459 §2.2: "Because of IRC's Scandinavian origin, the characters `{}|^`
/// are considered to be the lower case equivalents of the characters `[]\~`."
/// Folding a nickname with Unicode rules instead gets both halves wrong: it
/// misses those four pairs and folds letters no server does.
@Suite("Name case folding")
@MainActor
struct IRCSpecCasemappingTests {
	private func client(nickname: String = "me") -> GLTTestClient {
		GLTTestClient(configDictionary: ["nickname": nickname, "username": nickname])
	}

	private func joinedChannel(_ name: String, on client: GLTTestClient) throws -> Channel {
		let channel = try #require(client.findChannelOrCreate(name))

		channel.activate()

		return channel
	}

	private func deliver(_ line: String, on client: GLTTestClient) throws {
		let message = try #require(Message(line: line, on: client))

		client.forwardsProcessedMessages = true
		client.processIncomingMessage(message)
	}

	// MARK: - Ignore masks

	/// An ignore is written against a nickname, so it folds the way the server
	/// folds nicknames: `nick[home]` and `nick{home}` are one user.
	@Test("An ignore mask folds the RFC 1459 §2.2 pairs")
	func ignoreMasksFoldTheScandinavianPairs() {
		let matcher = AddressBookEntryMatcher(entryType: .ignore, hostmask: "nick[home]!*@*")

		#expect(matcher.matches(hostmask: "nick[home]!user@example.org"))
		#expect(matcher.matches(hostmask: "nick{home}!user@example.org"))
		#expect(matcher.matches(hostmask: "NICK{HOME}!user@example.org"))
		#expect(matcher.matches(hostmask: "nick(home)!user@example.org") == false)
	}

	@Test(
		"An ignore mask folds every RFC 1459 §2.2 pair",
		arguments: [
			IRCSpecCaseFoldPair(mask: "a[b", upper: "a[b", lower: "a{b"),
			IRCSpecCaseFoldPair(mask: "a]b", upper: "a]b", lower: "a}b"),
			// A literal backslash in a mask is written escaped, because `\` is
			// the glob's escape character as well as the upper-case form of `|`.
			IRCSpecCaseFoldPair(mask: #"a\\b"#, upper: #"a\b"#, lower: "a|b"),
			IRCSpecCaseFoldPair(mask: "a~b", upper: "a~b", lower: "a^b"),
		]
	)
	func everyPairFolds(_ pair: IRCSpecCaseFoldPair) {
		let matcher = AddressBookEntryMatcher(entryType: .ignore, hostmask: "\(pair.mask)!*@*")

		#expect(matcher.matches(hostmask: "\(pair.lower)!user@example.org"))
		#expect(matcher.matches(hostmask: "\(pair.upper)!user@example.org"))
	}

	/// The escape character survives folding: a mask escaping a wildcard still
	/// means the wildcard literally, even though `\` folds to `|`.
	@Test("Folding does not eat the glob's escape character")
	func foldingKeepsTheEscapeCharacter() {
		let matcher = AddressBookEntryMatcher(entryType: .ignore, hostmask: #"a\*b!*@*"#)

		#expect(matcher.matches(hostmask: "a*b!user@example.org"))
		#expect(matcher.matches(hostmask: "anythingb!user@example.org") == false)
	}

	/// Folding stops at ASCII. `İ` lower-cases to `i` in Unicode but is its own
	/// character on the wire, so an ignore on one must not catch the other.
	@Test("An ignore mask does not fold non-ASCII letters")
	func ignoreMasksDoNotFoldNonASCII() {
		let matcher = AddressBookEntryMatcher(entryType: .ignore, hostmask: "İrfan!*@*")

		#expect(matcher.matches(hostmask: "İrfan!user@example.org"))
		#expect(matcher.matches(hostmask: "irfan!user@example.org") == false)
	}

	/// One casemapping governs the whole address book. A tracking entry used to
	/// match with Unicode case folding, so it missed the pairs an ignore for the
	/// same nickname caught.
	@Test("A user-tracking entry folds the RFC 1459 §2.2 pairs too")
	func userTrackingEntriesFoldTheScandinavianPairs() {
		let matcher = AddressBookEntryMatcher(entryType: .userTracking, hostmask: "nick[home]")

		#expect(matcher.trackingNickname == "nick[home]")
		#expect(matcher.matches(hostmask: "nick[home]!user@example.org"))
		#expect(matcher.matches(hostmask: "nick{home}!user@example.org"))
		#expect(matcher.matches(hostmask: "NICK{HOME}!user@example.org"))
		#expect(matcher.matches(hostmask: "nick(home)!user@example.org") == false)
	}

	/// A tracked nickname is a name, not a mask: a wildcard in it matches
	/// itself, as it did when the entry compiled to an escaped expression.
	@Test("A user-tracking entry treats a wildcard in the nickname literally")
	func userTrackingEntriesTreatWildcardsLiterally() {
		let matcher = AddressBookEntryMatcher(entryType: .userTracking, hostmask: "ni*ck")

		#expect(matcher.matches(hostmask: "ni*ck!user@example.org"))
		#expect(matcher.matches(hostmask: "nianythingck!user@example.org") == false)
	}

	/// The mapping is a parameter: `ascii` folds A–Z only, so the four pairs
	/// stay distinct on a server that says so.
	@Test("CASEMAPPING=ascii leaves the four pairs distinct")
	func asciiMappingLeavesThePairsDistinct() {
		let matcher = AddressBookEntryMatcher(
			entryType: .ignore,
			hostmask: "nick[home]!*@*",
			caseMapping: .ascii
		)

		#expect(matcher.matches(hostmask: "NICK[HOME]!user@example.org"))
		#expect(matcher.matches(hostmask: "nick{home}!user@example.org") == false)
	}

	// MARK: - Query windows

	/// RFC 2812 §3.1.7: a QUIT closes the query with that user, and which
	/// query that is has to be decided with the server's folding.
	@Test("QUIT closes the query whose name folds to the sender")
	func quitClosesTheFoldedQuery() throws {
		let client = client()
		let query = try #require(client.findChannelOrCreate("nick{home}", as: .privateMessage))

		query.activate()

		try deliver(":nick[home]!u@example.org QUIT :Client Quit", on: client)

		#expect(query.isActive == false)
	}

	/// RFC 2812 §3.1.2: the same folding decides which query a NICK renames.
	@Test("NICK renames the query whose name folds to the old nickname")
	func nickRenamesTheFoldedQuery() throws {
		let client = client()
		let query = try #require(client.findChannelOrCreate("nick{home}", as: .privateMessage))

		query.activate()

		try deliver(":nick[home]!u@example.org NICK :newnick", on: client)

		#expect(query.name == "newnick")
	}

	/// A query that does not fold to the sender is somebody else's and stays
	/// open.
	@Test("QUIT leaves an unrelated query alone")
	func quitLeavesUnrelatedQueriesAlone() throws {
		let client = client()
		let query = try #require(client.findChannelOrCreate("someone", as: .privateMessage))

		query.activate()

		try deliver(":nick[home]!u@example.org QUIT :Client Quit", on: client)

		#expect(query.isActive)
	}
}
