// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing

/// Records what the protocol layer reported about a listing.
@MainActor
private final class RecordingChannelListPresentation: ChannelListPresenting {
	private(set) var events: [String] = []

	func openChannelList(for _: ServerSession) {
		events.append("open")
	}

	func closeChannelList(for _: ServerSession) {
		events.append("close")
	}

	func channelListDidStart(for _: ServerSession) {
		events.append("start")
	}

	func channelListDidReceive(channelNamed name: String, memberCount: UInt, topic: String?, for _: ServerSession) {
		events.append("\(name) \(memberCount) \(topic ?? "")")
	}

	func channelListDidFinish(for _: ServerSession) {
		events.append("finish")
	}
}

@MainActor
@Suite("Server channel list", .timeLimit(.minutes(1)))
struct ServerChannelListTests {
	private func receive(_ line: String, on session: TestServerSession) throws {
		try session.receiveNumericReply(#require(Message(line: line, on: session)))
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

	@Test("The listing replies, and a refused LIST, reach the presentation the session was given")
	func listingRepliesReachThePresentation() throws {
		let session = TestServerSession()
		let presentation = RecordingChannelListPresentation()
		session.environment.services.channelList = presentation

		try receive(":irc.example.net 321 me Channel :Users Name", on: session)
		try receive(":irc.example.net 322 me #swift 12 :All about Swift", on: session)
		try receive(":irc.example.net 323 me :End of /LIST", on: session)
		try receive(":irc.example.net 421 me LIST :Unknown command", on: session)

		#expect(presentation.events == ["start", "#swift 12 All about Swift", "finish", "finish"])
	}

	/** A reply for a window that is already closed used to make a new session,
	 and making a session sent `LIST` again: closing the list in the middle of a
	 listing asked the server for the whole thing a second time. */
	@Test("A listing reply for a list nobody has open neither opens one nor asks the server again")
	func replyWithoutAnOpenListIsDropped() {
		let windows = ServerChannelListWindowSessions()
		let session = TestServerSession()
		session.markAsLoggedIn()

		windows.channelListDidStart(for: session)
		windows.channelListDidReceive(channelNamed: "#swift", memberCount: 12, topic: nil, for: session)
		windows.channelListDidFinish(for: session)

		#expect(windows.list(for: session.uniqueIdentifier) == nil)
		#expect(session.sentLines.count == 0)
	}

	@Test("A refresh a session cannot send does not leave the list waiting")
	func refreshWhileLoggedOutEndsAtOnce() {
		let session = TestServerSession()
		let list = ServerChannelList(session: session)

		list.beginRefresh()

		#expect(list.model.isRefreshing == false)
		#expect(session.sentLines.count == 0)
	}

	@Test("A listing the server never finishes stops waiting once replies stop")
	func unfinishedListingTimesOut() async {
		let session = TestServerSession()
		session.markAsLoggedIn()
		let list = ServerChannelList(session: session, replyTimeout: 0.05)

		list.beginRefresh()
		#expect(list.model.isRefreshing)
		#expect(session.sentLines.count == 1)
		list.addChannel("#swift", count: 12, topic: nil)

		await refreshEnded(in: list.model)
		#expect(list.model.rows.map(\.channelName) == ["#swift"])
		list.close()
	}

	@Test("A listing ends when the connection it was asked on logs out")
	func disconnectEndsTheListing() async {
		let session = TestServerSession()
		session.markAsLoggedIn()
		let list = ServerChannelList(session: session, replyTimeout: 3600)

		list.beginRefresh()
		#expect(list.model.isRefreshing)
		session.isLoggedIn = false

		await refreshEnded(in: list.model)
		list.close()
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
		fill(model, with: [entry(name: "#dup", count: 1), entry(name: "#dup", count: 1)])
		await rowsUpdated(in: model)

		#expect(model.rows.count == 2)
		#expect(Set(model.rows.map(\.id)).count == 2)
	}

	/** The window used to cap the selection at eight and drop the rest without
	 saying so. What a JOIN may carry is the server's business -- CHANNELLEN and
	 the CHANLIMIT warning both live on the session -- so the table keeps whatever
	 was selected. */
	@Test("Selecting more rows than one JOIN would carry keeps every one of them")
	func selectionIsNotCapped() async {
		let model = ServerChannelListModel()
		fill(model, with: (0 ..< 10).map { entry(name: "#\($0)", count: $0) })
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

	@Test("A listing longer than the cap keeps the cap and counts the rest")
	func longListingIsCapped() async {
		let model = ServerChannelListModel()
		let entries = (0 ..< (ServerChannelListModel.maximumEntryCount + 3)).map {
			ServerChannelListEntry(channelName: "#channel\($0)", memberCount: 1)
		}

		fill(model, with: entries)
		await rowsUpdated(in: model)

		#expect(model.rows.count == ServerChannelListModel.maximumEntryCount)
		#expect(model.discardedEntryCount == 3)
	}

	@Test("Clearing the list forgets that anything was discarded")
	func clearingResetsTruncation() {
		let model = ServerChannelListModel()
		fill(model, with: (0 ..< (ServerChannelListModel.maximumEntryCount + 1)).map {
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

	@Test("Truncating a long Unicode topic preserves complete characters")
	func topicTruncationPreservesCharacters() {
		let character = "👩🏽‍💻"
		let topic = String(repeating: character, count: ServerChannelListModel.maximumDisplayedTopicLength + 1)
		let entry = ServerChannelListEntry(channelName: "#chat", unformattedTopic: topic)
		#expect(entry.displayedTopic == String(repeating: character, count: ServerChannelListModel.maximumDisplayedTopicLength) + "…")
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

		fill(model, with: entries)
		model.cancelPendingWrites()
		await rowsUpdated(in: model)
		#expect(model.rows.isEmpty)
	}

	private func populatedModel() async -> ServerChannelListModel {
		let model = ServerChannelListModel()
		fill(model, with: entries)
		await rowsUpdated(in: model)
		return model
	}

	private func entry(name: String, count: Int, topic: String = "") -> ServerChannelListEntry {
		ServerChannelListEntry(channelName: name, memberCount: count, unformattedTopic: topic)
	}

	/// Fills the model the way a listing does: one reply at a time, then the
	/// write the model batches them into.
	private func fill(_ model: ServerChannelListModel, with entries: [ServerChannelListEntry]) {
		for entry in entries {
			model.enqueue(
				channelName: entry.channelName,
				memberCount: UInt(entry.memberCount),
				topic: entry.unformattedTopic
			)
		}

		model.flushQueuedEntries()
	}
}
