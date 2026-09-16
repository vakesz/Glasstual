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

/// Records what the protocol layer reported about a listing.
@MainActor
private final class RecordingChannelListPresentation: ClientChannelListPresenting {
	private(set) var events: [String] = []

	func openChannelList(for _: IRCClient) {
		events.append("open")
	}

	func closeChannelList(for _: IRCClient) {
		events.append("close")
	}

	func channelListDidStart(for _: IRCClient) {
		events.append("start")
	}

	func channelListDidReceive(channelNamed name: String, memberCount: UInt, topic: String?, for _: IRCClient) {
		events.append("\(name) \(memberCount) \(topic ?? "")")
	}

	func channelListDidFinish(for _: IRCClient) {
		events.append("finish")
	}
}

@MainActor
@Suite("Server channel list", .timeLimit(.minutes(1)))
struct ServerChannelListTests {
	private func receive(_ line: String, on client: TestClient) throws {
		try client.receiveNumericReply(#require(Message(line: line, on: client)))
	}

	/// Waits for the list to stop spinning, however it gets there.
	private func refreshEnded(in model: ServerChannelListModel) async {
		for await refreshing in Observations({ model.isRefreshing }) where refreshing == false {
			await rowsUpdated(in: model)
			return
		}
	}

	private func rowsUpdated(in model: ServerChannelListModel) async {
		for await filtering in Observations({ model.isFiltering }) where filtering == false {
			return
		}
	}

	@Test("The listing replies, and a refused LIST, reach the presentation the client was given")
	func listingRepliesReachThePresentation() throws {
		let client = TestClient()
		let presentation = RecordingChannelListPresentation()
		client.environment.services.channelList = presentation

		try receive(":irc.example.net 321 me Channel :Users Name", on: client)
		try receive(":irc.example.net 322 me #swift 12 :All about Swift", on: client)
		try receive(":irc.example.net 323 me :End of /LIST", on: client)
		try receive(":irc.example.net 421 me LIST :Unknown command", on: client)

		#expect(presentation.events == ["start", "#swift 12 All about Swift", "finish", "finish"])
	}

	/** A reply for a window that is already closed used to make a new session,
	 and making a session sent `LIST` again: closing the list in the middle of a
	 listing asked the server for the whole thing a second time. */
	@Test("A listing reply for a list nobody has open neither opens one nor asks the server again")
	func replyWithoutAnOpenListIsDropped() {
		let scenes = ApplicationScenes()
		let client = TestClient()
		client.markAsLoggedIn()

		scenes.channelListDidStart(for: client)
		scenes.channelListDidReceive(channelNamed: "#swift", memberCount: 12, topic: nil, for: client)
		scenes.channelListDidFinish(for: client)

		#expect(scenes.serverChannelList(for: client.uniqueIdentifier) == nil)
		#expect(client.sentLines.count == 0)
	}

	@Test("A refresh a client cannot send does not leave the list waiting")
	func refreshWhileLoggedOutEndsAtOnce() {
		let client = TestClient()
		let session = ServerChannelListSession(client: client)

		session.beginRefresh()

		#expect(session.model.isRefreshing == false)
		#expect(client.sentLines.count == 0)
	}

	@Test("A listing the server never finishes stops waiting once replies stop")
	func unfinishedListingTimesOut() async {
		let client = TestClient()
		client.markAsLoggedIn()
		let session = ServerChannelListSession(client: client, replyTimeout: .milliseconds(50))

		session.beginRefresh()
		#expect(session.model.isRefreshing)
		#expect(client.sentLines.count == 1)
		session.addChannel("#swift", count: 12, topic: nil)

		await refreshEnded(in: session.model)
		#expect(session.model.rows.map(\.channelName) == ["#swift"])
		session.close()
	}

	@Test("A listing ends when the connection it was asked on logs out")
	func disconnectEndsTheListing() async {
		let client = TestClient()
		client.markAsLoggedIn()
		let session = ServerChannelListSession(client: client, replyTimeout: .seconds(3600))

		session.beginRefresh()
		#expect(session.model.isRefreshing)
		client.isLoggedIn = false

		await refreshEnded(in: session.model)
		session.close()
	}

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
	func oversizedMemberCountIsSaturated() async {
		let model = ServerChannelListModel()

		model.enqueue(channelName: "#huge", memberCount: .max, topic: nil)
		model.flushQueuedEntries()
		await rowsUpdated(in: model)

		#expect(model.rows.map(\.memberCount) == [.max])
	}

	@Test("The native table starts with the largest channels first")
	func defaultSortIsDescendingMemberCount() async {
		let model = await populatedModel()

		#expect(model.rows.map(\.channelName) == ["#Rust", "#swift", "#cocoa"])
	}

	@Test("Search matches channel names and topics without case sensitivity")
	func searchMatchesNamesAndTopics() async {
		let model = await populatedModel()

		/* Typing is debounced; the matching itself is what is under test. */
		model.searchString = "RUST"
		model.applyFilterAndSort()
		await rowsUpdated(in: model)
		#expect(model.rows.map(\.channelName) == ["#Rust"])

		model.searchString = "appkit"
		model.applyFilterAndSort()
		await rowsUpdated(in: model)
		#expect(model.rows.map(\.channelName) == ["#cocoa"])

		model.searchString = "   "
		model.applyFilterAndSort()
		await rowsUpdated(in: model)
		#expect(model.rows.count == 3)
	}

	@Test("Changing a column sort reorders the model")
	func typedSortOrderReordersRows() async {
		let model = await populatedModel()

		model.sortOrder = [ServerChannelListComparator(field: .channelName, order: .forward)]
		await rowsUpdated(in: model)

		#expect(model.rows.map(\.channelName) == ["#cocoa", "#Rust", "#swift"])
	}

	@Test("Topic sorting ignores letter case")
	func topicSortIsCaseInsensitive() async {
		let model = await populatedModel()

		model.sortOrder = [ServerChannelListComparator(field: .topic, order: .forward)]
		await rowsUpdated(in: model)

		#expect(model.rows.map(\.channelName) == ["#swift", "#cocoa", "#Rust"])
	}

	@Test("Two same-named channels remain distinct rows")
	func duplicateNamesKeepDistinctIdentity() async {
		let model = ServerChannelListModel()
		model.replace(with: [entry(name: "#dup", count: 1), entry(name: "#dup", count: 1)])
		await rowsUpdated(in: model)

		#expect(model.rows.count == 2)
		#expect(Set(model.rows.map(\.id)).count == 2)
	}

	/** The window used to cap the selection at eight and drop the rest without
	 saying so. What a JOIN may carry is the server's business -- CHANNELLEN and
	 the CHANLIMIT warning both live on the client -- so the table keeps whatever
	 was selected. */
	@Test("Selecting more rows than one JOIN would carry keeps every one of them")
	func selectionIsNotCapped() async {
		let model = ServerChannelListModel()
		model.replace(with: (0 ..< 10).map { entry(name: "#\($0)", count: $0) })
		await rowsUpdated(in: model)

		model.selection = Set(model.rows.map(\.id))

		#expect(model.selection.count == 10)
		#expect(model.selectedChannelNames.count == 10)
	}

	@Test("Clearing cancels queued server replies")
	func clearDiscardsQueuedEntries() {
		let model = ServerChannelListModel()
		model.enqueue(channelName: "#old", memberCount: 10, topic: nil)

		model.clear()
		model.flushQueuedEntries()

		#expect(model.rows.isEmpty)
	}

	@Test("Finishing a refresh publishes its final queued replies")
	func finishRefreshFlushesEntries() async {
		let model = ServerChannelListModel()
		model.enqueue(channelName: "#swift", memberCount: 120, topic: "Swift")

		model.finishRefresh()
		await rowsUpdated(in: model)

		#expect(model.rows.map(\.channelName) == ["#swift"])
		#expect(model.isRefreshing == false)
	}

	@Test("Server-side ELIST arguments use only capabilities the server advertises")
	func extendedListArguments() {
		#expect(ServerChannelListModel.listArguments(
			minimumUserCount: 10,
			supportedTokens: ["U", "M"]
		) == ">9")
		#expect(ServerChannelListModel.listArguments(
			minimumUserCount: 10,
			supportedTokens: []
		) == nil)
		#expect(ServerChannelListModel.listArguments(
			minimumUserCount: 10,
			supportedTokens: ["M"]
		) == nil)
	}

	@Test("Copying selected channels produces one visible tabular item")
	func copySelection() async throws {
		let model = await populatedModel()
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
	func entriesAreCapped() async {
		let model = ServerChannelListModel()
		let overflow = 5

		for index in 0 ..< (ServerChannelListModel.maximumEntryCount + overflow) {
			model.enqueue(channelName: "#channel\(index)", memberCount: 1, topic: nil)
		}
		model.flushQueuedEntries()
		await rowsUpdated(in: model)

		#expect(model.rows.count == ServerChannelListModel.maximumEntryCount)
		#expect(model.discardedEntryCount == overflow)
		#expect(model.truncationNotice != nil)
	}

	/** The notice counts what the window kept, which the search field does not
	 change. It used to read as the number of channels on screen, so typing
	 anything into the search field made it a count of rows that were not there. */
	@Test("The truncation notice is about what was kept, not what is on screen")
	func truncationNoticeCountsWhatWasKept() async {
		let model = ServerChannelListModel()

		for index in 0 ..< (ServerChannelListModel.maximumEntryCount + 1) {
			model.enqueue(channelName: "#channel\(index)", memberCount: 1, topic: nil)
		}
		model.flushQueuedEntries()
		await rowsUpdated(in: model)

		let notice = model.truncationNotice
		#expect(notice != nil)

		model.searchString = "#channel1"
		model.applyFilterAndSort()
		await rowsUpdated(in: model)

		#expect(model.rows.count < ServerChannelListModel.maximumEntryCount)
		#expect(model.truncationNotice == notice)
	}

	/** The window's subtitle counts what arrived, not what is on screen: it used
	 to count the table's rows, so typing anything into the search field made the
	 title a count of channels the server had never stopped sending. */
	@Test("The window's channel count is what was kept, not what the search left")
	func keptEntryCountIgnoresTheSearchField() async {
		let model = await populatedModel()
		let kept = model.keptEntryCount
		#expect(kept == model.rows.count)

		model.searchString = "#swift"
		model.applyFilterAndSort()
		await rowsUpdated(in: model)

		#expect(model.rows.count == 1)
		#expect(model.keptEntryCount == kept)
	}

	@Test("A complete list says nothing about truncation")
	func completeListHasNoNotice() async {
		let model = await populatedModel()

		#expect(model.discardedEntryCount == 0)
		#expect(model.truncationNotice == nil)
	}

	@Test("Replacing the entries wholesale is capped the same way")
	func replacementIsCapped() async {
		let model = ServerChannelListModel()
		let entries = (0 ..< (ServerChannelListModel.maximumEntryCount + 3)).map {
			ServerChannelListEntry(channelName: "#channel\($0)", memberCount: 1)
		}

		model.replace(with: entries)
		await rowsUpdated(in: model)

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
	func filteringIsDebounced() async {
		let model = await populatedModel()
		let everything = model.rows.count

		model.searchString = "Rust"
		#expect(model.rows.count == everything, "Filtering on each keystroke is what made typing slow")

		await rowsUpdated(in: model)
		#expect(model.rows.count < everything)
		#expect(model.rows.allSatisfy { $0.matches("Rust") })
	}

	@Test("Refresh keeps topic matches available and clearing search restores every retained row")
	func refreshPreservesLocalSearchSemantics() async {
		let model = await populatedModel()
		model.searchString = "appkit"
		#expect(model.listArguments(supportedTokens: ["U", "M"]) == nil)
		model.beginRefresh()
		for entry in entries {
			model.enqueue(channelName: entry.channelName, memberCount: UInt(entry.memberCount), topic: entry.unformattedTopic)
		}
		model.finishRefresh()
		await rowsUpdated(in: model)
		#expect(model.rows.map(\.channelName) == ["#cocoa"])

		model.searchString = ""
		await rowsUpdated(in: model)
		#expect(model.rows.count == entries.count)
	}

	@Test("A replacement query publishes only its own matching rows and selection")
	func latestQueryWins() async {
		let model = await populatedModel()
		model.selection = Set(model.rows.map(\.id))
		model.searchString = "Rust"
		model.applyFilterAndSort()
		model.searchString = "AppKit"
		await rowsUpdated(in: model)

		#expect(model.rows.map(\.channelName) == ["#cocoa"])
		#expect(model.selection == Set(model.rows.map(\.id)))
	}

	@Test("Clearing and closing discard a pending filter without republishing old rows")
	func clearingCancelsPendingFilter() async {
		let model = await populatedModel()
		model.searchString = "Swift"
		model.clear()
		await rowsUpdated(in: model)
		#expect(model.rows.isEmpty)
		#expect(model.isFiltering == false)

		model.replace(with: entries)
		model.cancelPendingWrites()
		await rowsUpdated(in: model)
		#expect(model.rows.isEmpty)
	}

	private func populatedModel() async -> ServerChannelListModel {
		let model = ServerChannelListModel()
		model.replace(with: entries)
		await rowsUpdated(in: model)
		return model
	}

	private func entry(name: String, count: Int, topic: String = "") -> ServerChannelListEntry {
		ServerChannelListEntry(channelName: name, memberCount: count, unformattedTopic: topic)
	}
}
