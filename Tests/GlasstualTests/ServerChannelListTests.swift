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

@MainActor
@Suite("Server channel list")
struct ServerChannelListTests {
	private var entries: [ServerChannelListEntry] {
		[
			entry(name: "#swift", count: 120, topic: "All about Swift"),
			entry(name: "#cocoa", count: 40, topic: "AppKit and friends"),
			entry(name: "#Rust", count: 300, topic: "systems programming"),
		]
	}

	/// `RPL_LIST` carries whatever the server decided to put in the field, and
	/// a count that does not fit an `Int` used to end the process.
	@Test("A member count too large for the row is saturated rather than fatal")
	func oversizedMemberCountIsSaturated() {
		let model = ServerChannelListModel()

		model.enqueue(channelName: "#huge", memberCount: .max, topic: nil)
		model.flushQueuedEntries()

		#expect(model.rows.map(\.memberCount) == [.max])
	}

	@Test("The native table starts with the largest channels first")
	func defaultSortIsDescendingMemberCount() {
		let model = populatedModel()

		#expect(model.rows.map(\.channelName) == ["#Rust", "#swift", "#cocoa"])
	}

	@Test("Search matches channel names and topics without case sensitivity")
	func searchMatchesNamesAndTopics() {
		let model = populatedModel()

		/* Typing is debounced; the matching itself is what is under test. */
		model.searchString = "RUST"
		model.applyFilterAndSort()
		#expect(model.rows.map(\.channelName) == ["#Rust"])

		model.searchString = "appkit"
		model.applyFilterAndSort()
		#expect(model.rows.map(\.channelName) == ["#cocoa"])

		model.searchString = "   "
		model.applyFilterAndSort()
		#expect(model.rows.count == 3)
	}

	@Test("Changing a column sort reorders the model")
	func typedSortOrderReordersRows() {
		let model = populatedModel()

		model.sortOrder = [ServerChannelListComparator(field: .channelName, order: .forward)]

		#expect(model.rows.map(\.channelName) == ["#cocoa", "#Rust", "#swift"])
	}

	@Test("Topic sorting ignores letter case")
	func topicSortIsCaseInsensitive() {
		let model = populatedModel()

		model.sortOrder = [ServerChannelListComparator(field: .topic, order: .forward)]

		#expect(model.rows.map(\.channelName) == ["#swift", "#cocoa", "#Rust"])
	}

	@Test("Two same-named channels remain distinct rows")
	func duplicateNamesKeepDistinctIdentity() {
		let model = ServerChannelListModel()
		model.replace(with: [entry(name: "#dup", count: 1), entry(name: "#dup", count: 1)])

		#expect(model.rows.count == 2)
		#expect(Set(model.rows.map(\.id)).count == 2)
	}

	@Test("Selection is capped at eight rows")
	func selectionLimit() {
		let model = ServerChannelListModel()
		model.replace(with: (0 ..< 10).map { entry(name: "#\($0)", count: $0) })
		model.selection = Set(model.rows.map(\.id))

		model.limitSelection(from: [])

		#expect(model.selection.count == ServerChannelListModel.maximumSelectionCount)
	}

	@Test("Clearing cancels queued server replies")
	func clearDiscardsQueuedEntries() {
		let model = ServerChannelListModel()
		model.enqueue(channelName: "#old", memberCount: 10, topic: nil)

		model.clear()
		model.flushQueuedEntries()

		#expect(model.rows.isEmpty)
	}

	@Test("Finishing a refresh immediately publishes its final queued replies")
	func finishRefreshFlushesEntries() {
		let model = ServerChannelListModel()
		model.enqueue(channelName: "#swift", memberCount: 120, topic: "Swift")

		model.finishRefresh()

		#expect(model.rows.map(\.channelName) == ["#swift"])
		#expect(model.isRefreshing == false)
	}

	@Test("Server-side ELIST arguments use only capabilities the server advertises")
	func extendedListArguments() {
		#expect(ServerChannelListModel.listArguments(
			minimumUserCount: 10,
			pattern: "swift",
			supportedTokens: ["U", "M"]
		) == ">9,*swift*")
		#expect(ServerChannelListModel.listArguments(
			minimumUserCount: 10,
			pattern: "swift",
			supportedTokens: []
		) == nil)
		#expect(ServerChannelListModel.listArguments(
			minimumUserCount: 10,
			pattern: "bad,pattern",
			supportedTokens: ["U", "M"]
		) == ">9")
	}

	@Test("Copying selected channels produces one visible tabular item")
	func copySelection() throws {
		let model = populatedModel()
		model.selection = Set(model.rows.prefix(2).map(\.id))

		let copied = try #require(model.selectedCopyItems.first)

		#expect(model.selectedCopyItems.count == 1)
		#expect(copied.contains("#Rust\t300\tsystems programming"))
		#expect(copied.contains("\n"))
	}

	@Test("The channel-list scene no longer bundles a nib")
	func nativeSceneHasNoNib() {
		#expect(Bundle.main.path(forResource: "TDCServerChannelListDialog", ofType: "nib") == nil)
	}

	@Test("The list stops growing at its cap and says how much it is showing")
	func entriesAreCapped() {
		let model = ServerChannelListModel()
		let overflow = 5

		for index in 0 ..< (ServerChannelListModel.maximumEntryCount + overflow) {
			model.enqueue(channelName: "#channel\(index)", memberCount: 1, topic: nil)
		}
		model.flushQueuedEntries()

		#expect(model.rows.count == ServerChannelListModel.maximumEntryCount)
		#expect(model.discardedEntryCount == overflow)
		#expect(model.truncationNotice != nil)
	}

	/** The notice counts what the window kept, which the search field does not
	 change. It used to read as the number of channels on screen, so typing
	 anything into the search field made it a count of rows that were not there. */
	@Test("The truncation notice is about what was kept, not what is on screen")
	func truncationNoticeCountsWhatWasKept() {
		let model = ServerChannelListModel()

		for index in 0 ..< (ServerChannelListModel.maximumEntryCount + 1) {
			model.enqueue(channelName: "#channel\(index)", memberCount: 1, topic: nil)
		}
		model.flushQueuedEntries()

		let notice = model.truncationNotice
		#expect(notice != nil)

		model.searchString = "#channel1"
		model.applyFilterAndSort()

		#expect(model.rows.count < ServerChannelListModel.maximumEntryCount)
		#expect(model.truncationNotice == notice)
	}

	@Test("A complete list says nothing about truncation")
	func completeListHasNoNotice() {
		let model = populatedModel()

		#expect(model.discardedEntryCount == 0)
		#expect(model.truncationNotice == nil)
	}

	@Test("Replacing the entries wholesale is capped the same way")
	func replacementIsCapped() {
		let model = ServerChannelListModel()
		let entries = (0 ..< (ServerChannelListModel.maximumEntryCount + 3)).map {
			ServerChannelListEntry(channelName: "#channel\($0)", memberCount: 1)
		}

		model.replace(with: entries)

		#expect(model.rows.count == ServerChannelListModel.maximumEntryCount)
		#expect(model.discardedEntryCount == 3)
	}

	@Test("Clearing the list forgets that anything was discarded")
	func clearingResetsTruncation() {
		let model = ServerChannelListModel()
		model.replace(with: (0 ..< (ServerChannelListModel.maximumEntryCount + 1)).map {
			ServerChannelListEntry(channelName: "#channel\($0)", memberCount: 1)
		})

		model.clear()

		#expect(model.discardedEntryCount == 0)
		#expect(model.truncationNotice == nil)
	}

	@Test("A long topic is drawn bounded and kept whole for copying")
	func longTopicsAreTruncatedForDisplay() {
		let topic = String(repeating: "t", count: ServerChannelListModel.maximumDisplayedTopicLength + 50)
		let entry = ServerChannelListEntry(channelName: "#chat", memberCount: 1, unformattedTopic: topic)

		#expect(entry.displayedTopic.count == ServerChannelListModel.maximumDisplayedTopicLength + 1)
		#expect(entry.displayedTopic.hasSuffix("…"))
		#expect(entry.unformattedTopic == topic)
		#expect(entry.copyText.contains(topic))
	}

	@Test("A topic that fits is shown as it is")
	func shortTopicsAreLeftAlone() {
		let entry = ServerChannelListEntry(channelName: "#chat", memberCount: 1, unformattedTopic: "systems")

		#expect(entry.displayedTopic == "systems")
	}

	@Test("Typing does not filter until it stops, and the filter still runs")
	func filteringIsDebounced() async throws {
		let model = populatedModel()
		let everything = model.rows.count

		model.searchString = "Rust"
		#expect(model.rows.count == everything, "Filtering on each keystroke is what made typing slow")

		try await Task.sleep(for: ServerChannelListModel.filterDelay + .milliseconds(250))
		#expect(model.rows.count < everything)
		#expect(model.rows.allSatisfy { $0.matches("Rust") })
	}

	private func populatedModel() -> ServerChannelListModel {
		let model = ServerChannelListModel()
		model.replace(with: entries)
		return model
	}

	private func entry(name: String, count: Int, topic: String = "") -> ServerChannelListEntry {
		ServerChannelListEntry(channelName: name, memberCount: count, unformattedTopic: topic)
	}
}
