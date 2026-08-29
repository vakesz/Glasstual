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
import Testing

/// What the channel-list table draws for a given search and sort.
///
/// The search used to be an `NSPredicate` written into the nib and the sort a
/// binding, so neither could be reached from a test at all.
@Suite("Server channel list rows")
struct ServerChannelListDialogTableTests {
	private var entries: [ServerChannelListDialogEntry] {
		[
			makeEntry(name: "#swift", count: 120, topic: "All about Swift"),
			makeEntry(name: "#cocoa", count: 40, topic: "AppKit and friends"),
			makeEntry(name: "#Rust", count: 300, topic: "systems programming"),
		]
	}

	// MARK: - Filtering

	@Test("With no search every channel is shown")
	func emptySearchShowsEverything() {
		#expect(names(matching: "") == ["#swift", "#cocoa", "#Rust"])
	}

	@Test("The search matches a channel name, ignoring case")
	func searchMatchesNameCaseInsensitively() {
		#expect(names(matching: "rust") == ["#Rust"])
		#expect(names(matching: "RUST") == ["#Rust"])
		#expect(names(matching: "#SW") == ["#swift"])
	}

	@Test("The search matches a topic, ignoring case")
	func searchMatchesTopicCaseInsensitively() {
		#expect(names(matching: "appkit") == ["#cocoa"])
		#expect(names(matching: "SYSTEMS") == ["#Rust"])
	}

	@Test("A search matching both a name and a topic keeps both channels")
	func searchMatchesNameOrTopic() {
		/* "swift" is the name of one channel and part of another's topic. */
		#expect(names(matching: "swift") == ["#swift"])
		#expect(names(matching: "a") == ["#swift", "#cocoa", "#Rust"])
	}

	@Test("A search that matches nothing empties the table")
	func searchWithNoMatchesShowsNothing() {
		#expect(names(matching: "erlang").isEmpty)
	}

	@Test("Clearing the search brings every channel back")
	func clearingTheSearchRestoresEverything() {
		#expect(names(matching: "rust") == ["#Rust"])
		#expect(names(matching: "") == ["#swift", "#cocoa", "#Rust"])
	}

	// MARK: - Sorting

	@Test("Member count sorts numerically, and descending is the dialog's default")
	func memberCountSortsNumerically() {
		#expect(
			names(sortedBy: "channelMemberCount", ascending: false) == ["#Rust", "#swift", "#cocoa"]
		)
		#expect(
			names(sortedBy: "channelMemberCount", ascending: true) == ["#cocoa", "#swift", "#Rust"]
		)
	}

	@Test("The topic column sorts on the unformatted topic, ignoring case")
	func topicSortsCaseInsensitively() {
		/* Topics are "All about Swift", "AppKit and friends" and "systems
		 programming". Compared literally, the lowercase "systems" would sort
		 ahead of both capitals; case-insensitively it sorts last. */
		#expect(
			names(sortedBy: "channelTopicUnformatted", ascending: true)
				== ["#swift", "#cocoa", "#Rust"]
		)
		#expect(
			names(sortedBy: "channelTopicUnformatted", ascending: false)
				== ["#Rust", "#cocoa", "#swift"]
		)
	}

	@Test("An unknown sort key leaves the order alone")
	func unknownSortKeyKeepsArrivalOrder() {
		#expect(names(sortedBy: "notAColumn", ascending: true) == ["#swift", "#cocoa", "#Rust"])
		#expect(names(sortedBy: nil, ascending: true) == ["#swift", "#cocoa", "#Rust"])
	}

	@Test("Filtering and sorting are applied together")
	func filterAndSortCompose() {
		let rows = ServerChannelListDialogEntry.rows(
			from: entries,
			matching: "u",
			sortedBy: "channelMemberCount",
			ascending: true
		)

		/* "u" is in "#Rust" and in "All about Swift", but in neither "#cocoa"
		 nor "AppKit and friends". */
		#expect(rows.map(\.channelName) == ["#swift", "#Rust"])
	}

	// MARK: - Identity

	@Test("Two channels with the same name are still two rows")
	func entriesAreDistinctByIdentity() {
		let duplicated = [makeEntry(name: "#dup", count: 1, topic: ""), makeEntry(name: "#dup", count: 1, topic: "")]
		let rows = ServerChannelListDialogEntry.rows(
			from: duplicated,
			matching: "",
			sortedBy: nil,
			ascending: true
		)

		#expect(rows.count == 2)
		#expect(Set(rows.map(\.id)).count == 2)
	}

	// MARK: - Helpers

	private func makeEntry(name: String, count: Int, topic: String) -> ServerChannelListDialogEntry {
		var entry = ServerChannelListDialogEntry()
		entry.channelName = name
		entry.channelMemberCount = count
		entry.channelTopicUnformatted = topic

		return entry
	}

	private func names(matching searchString: String) -> [String] {
		ServerChannelListDialogEntry.rows(
			from: entries,
			matching: searchString,
			sortedBy: nil,
			ascending: true
		)
		.map(\.channelName)
	}

	private func names(sortedBy sortKey: String?, ascending: Bool) -> [String] {
		ServerChannelListDialogEntry.rows(
			from: entries,
			matching: "",
			sortedBy: sortKey,
			ascending: ascending
		)
		.map(\.channelName)
	}
}
