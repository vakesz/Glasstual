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

	@Test("The native table starts with the largest channels first")
	func defaultSortIsDescendingMemberCount() {
		let model = populatedModel()

		#expect(model.rows.map(\.channelName) == ["#Rust", "#swift", "#cocoa"])
	}

	@Test("Search matches channel names and topics without case sensitivity")
	func searchMatchesNamesAndTopics() {
		let model = populatedModel()

		model.searchString = "RUST"
		#expect(model.rows.map(\.channelName) == ["#Rust"])

		model.searchString = "appkit"
		#expect(model.rows.map(\.channelName) == ["#cocoa"])

		model.searchString = "   "
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

	private func populatedModel() -> ServerChannelListModel {
		let model = ServerChannelListModel()
		model.replace(with: entries)
		return model
	}

	private func entry(name: String, count: Int, topic: String = "") -> ServerChannelListEntry {
		ServerChannelListEntry(channelName: name, memberCount: count, unformattedTopic: topic)
	}
}
