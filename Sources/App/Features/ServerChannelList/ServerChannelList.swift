/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
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

import Combine
import Foundation
import Observation

/// Owns one server's public-channel list and connects its SwiftUI scene to the
/// IRC client. Window lifecycle and restoration belong to SwiftUI.
@MainActor
final class ServerChannelList {
	let client: Client
	let model = ServerChannelListModel()

	/** How long a listing may go without a reply before the window stops
	 waiting for it.

	 `RPL_LISTEND` is the only reply that ends a listing, and plenty of paths
	 never send one: a server that throttles `LIST` answers with a notice or
	 an unlisted numeric, and a connection can go quiet without closing. The
	 limit counts from the last reply, so a network streaming a very long
	 listing is never cut off. */
	private let replyTimeout: TimeInterval
	private lazy var replyWatchdog = ClientTimer { [weak self] _ in
		self?.finishRefresh()
	}

	private var connectionObservation: Task<Void, Never>?

	init(client: Client, replyTimeout: TimeInterval = 60) {
		self.client = client
		self.replyTimeout = replyTimeout
		observeConnection()
	}

	isolated deinit {
		replyWatchdog.stop()
		connectionObservation?.cancel()
	}

	var clientIdentifier: String {
		client.uniqueIdentifier
	}

	var networkName: String {
		client.networkNameAlt
	}

	var supportsMinimumUserCount: Bool {
		client.supportInfo.extendedListSupportsToken("U")
	}

	var serverSideListArguments: String? {
		model.listArguments(supportedTokens: client.supportInfo.extendedListTokens)
	}

	/// Asks the server for a fresh listing. A client that is not logged in has
	/// nobody to ask, so the list does not wait for an answer.
	func beginRefresh() {
		model.beginRefresh()
		guard client.isLoggedIn else {
			finishRefresh()
			return
		}
		client.requestChannelList(withArguments: serverSideListArguments)
		noteReply()
	}

	func receiveListStart() {
		model.beginRefresh()
		noteReply()
	}

	func clear() {
		model.clear()
	}

	func addChannel(_ channel: String, count: UInt, topic: String?) {
		model.enqueue(channelName: channel, memberCount: count, topic: topic)
		if model.isRefreshing {
			noteReply()
		}
	}

	func finishRefresh() {
		replyWatchdog.stop()
		model.finishRefresh()
	}

	func joinSelectedChannels() {
		let channelNames = model.selectedChannelNames
		guard channelNames.isEmpty == false else { return }
		client.joinUnlistedChannelsAndSelectBestMatch(channelNames)
		model.clearSelection()
	}

	func close() {
		replyWatchdog.stop()
		connectionObservation?.cancel()
		connectionObservation = nil
		model.cancelPendingWrites()
	}

	/// Moves the deadline on: every reply starts the wait again, so a network
	/// streaming a very long listing is never cut off.
	private func noteReply() {
		replyWatchdog.start(replyTimeout)
	}

	/** A listing cannot outlive the registration it was asked on: the server
	 that would have finished it is gone.

	 The initial value is read too. The observation starts when its task first
	 runs, which can be after a logout that happened in the same turn as the
	 refresh; the value it starts from is what still catches that one. */
	private func observeConnection() {
		let client = client
		connectionObservation = Task { [weak self] in
			for await isLoggedIn in client.publisher(for: \.isLoggedIn, options: [.initial, .new]).bufferedValues {
				guard let self, !Task.isCancelled else { return }
				if isLoggedIn == false, model.isRefreshing {
					finishRefresh()
				}
			}
		}
	}
}

nonisolated struct ServerChannelListEntry: Identifiable, Hashable, Sendable { // nonisolated: value
	let id = UUID()
	var channelName = ""
	var memberCount = 0
	var unformattedTopic = ""

	/** The topic as the row shows it.

	 An RPL_LIST topic is unbounded server text and the column is one line, so
	 the row draws a bounded copy; the full text stays in `unformattedTopic` for
	 the tooltip and for copying. */
	var displayedTopic: String {
		let topic = unformattedTopic
		guard topic.count > ServerChannelListModel.maximumDisplayedTopicLength else { return topic }

		return String(topic.prefix(ServerChannelListModel.maximumDisplayedTopicLength)) + "\u{2026}"
	}

	func matches(_ searchString: String) -> Bool {
		guard searchString.isEmpty == false else { return true }
		return channelName.localizedCaseInsensitiveContains(searchString)
			|| unformattedTopic.localizedCaseInsensitiveContains(searchString)
	}

	var plainTopic: String {
		FormattingParser.parse(unformattedTopic).string
	}

	var copyText: String {
		"\(channelName)\t\(memberCount)\t\(plainTopic)"
	}
}

nonisolated struct ServerChannelListComparator: SortComparator { // nonisolated: value
	enum Field: Hashable, Sendable {
		case channelName
		case memberCount
		case topic
	}

	let field: Field
	var order: SortOrder

	func compare(_ lhs: ServerChannelListEntry, _ rhs: ServerChannelListEntry) -> ComparisonResult {
		let result: ComparisonResult = switch field {
		case .channelName:
			lhs.channelName.localizedCaseInsensitiveCompare(rhs.channelName)
		case .memberCount:
			lhs.memberCount == rhs.memberCount
				? .orderedSame
				: (lhs.memberCount < rhs.memberCount ? .orderedAscending : .orderedDescending)
		case .topic:
			lhs.unformattedTopic.localizedCaseInsensitiveCompare(rhs.unformattedTopic)
		}

		guard order == .reverse else { return result }
		return switch result {
		case .orderedAscending: .orderedDescending
		case .orderedDescending: .orderedAscending
		case .orderedSame: .orderedSame
		}
	}
}

@Observable
final class ServerChannelListModel {
	/** How many channels the window keeps.

	 A large network answers `LIST` with hundreds of thousands of rows, and
	 every one of them was kept, re-filtered and re-sorted on each keystroke.
	 What is past the cap is counted and reported, not silently dropped. */
	static let maximumEntryCount = 20000
	nonisolated static let maximumDisplayedTopicLength = 200 // nonisolated: let
	/// How long typing has to pause before the list is filtered again.
	static let filterDelay = Duration.milliseconds(120)

	private(set) var rows: [ServerChannelListEntry] = []
	var selection: Set<ServerChannelListEntry.ID> = []
	var searchString = "" {
		didSet {
			guard searchString != oldValue else { return }
			scheduleFilter()
		}
	}

	var minimumUserCount = ""
	var sortOrder: [ServerChannelListComparator] = [
		ServerChannelListComparator(field: .memberCount, order: .reverse),
	] {
		didSet { applyFilterAndSort() }
	}

	var isRefreshing = true
	private(set) var isFiltering = false

	/// How many channels the server sent past the cap. Zero means the list is
	/// complete.
	private(set) var discardedEntryCount = 0

	private var allEntries: [ServerChannelListEntry] = []
	private var queuedEntries: [ServerChannelListEntry] = []
	/// Writes the rows that arrived since the last flush, a second after the
	/// first of them landed. A reply arrives one line at a time, and a table
	/// rebuilt per line is a table nobody can read while it is filling.
	@ObservationIgnored private lazy var queuedWriteTimer = ClientTimer { [weak self] _ in
		self?.flushQueuedEntries()
	}

	@ObservationIgnored private var filterTask: Task<Void, Never>?

	/** What to tell the user when the list is not all of it, or `nil` when it is.

	 The count is what the window kept, not what the table is showing: the search
	 field narrows the rows further, and a notice that named the row count would
	 be wrong for as long as anything was typed into it. */
	var truncationNotice: String? {
		guard discardedEntryCount > 0 else { return nil }

		return String(localized: .ServerChannelList.listTruncatedNotice(allEntries.count))
	}

	/// How many channels the window kept, which the search field does not change.
	var keptEntryCount: Int {
		allEntries.count
	}

	var selectedChannelNames: [String] {
		rows.filter { selection.contains($0.id) }.map(\.channelName)
	}

	var selectedCopyItems: [String] {
		let selectedRows = rows.filter { selection.contains($0.id) }
		guard selectedRows.isEmpty == false else { return [] }
		return [selectedRows.map(\.copyText).joined(separator: "\n")]
	}

	func enqueue(channelName: String, memberCount: UInt, topic: String?) {
		guard allEntries.count + queuedEntries.count < Self.maximumEntryCount else {
			discardedEntryCount += 1
			return
		}

		queuedEntries.append(ServerChannelListEntry(
			channelName: channelName,
			/* The count comes off the wire as an unbounded RPL_LIST field, so
				it is saturated rather than trusted to fit. */
			memberCount: Int(clamping: memberCount),
			unformattedTopic: topic ?? ""
		))

		queuedWriteTimer.startIfIdle(1)
	}

	func flushQueuedEntries() {
		queuedWriteTimer.stop()
		guard queuedEntries.isEmpty == false else { return }
		allEntries.append(contentsOf: queuedEntries)
		queuedEntries.removeAll()
		applyFilterAndSort()
	}

	func beginRefresh() {
		isRefreshing = true
		clear()
	}

	func finishRefresh() {
		flushQueuedEntries()
		isRefreshing = false
	}

	func clear() {
		cancelPendingWrites()
		allEntries.removeAll()
		rows.removeAll()
		selection.removeAll()
		discardedEntryCount = 0
	}

	isolated deinit {
		queuedWriteTimer.stop()
		filterTask?.cancel()
	}

	func cancelPendingWrites() {
		queuedWriteTimer.stop()
		filterTask?.cancel()
		filterTask = nil
		isFiltering = false
		queuedEntries.removeAll()
	}

	func replace(with entries: [ServerChannelListEntry]) {
		cancelPendingWrites()
		allEntries = Array(entries.prefix(Self.maximumEntryCount))
		discardedEntryCount = entries.count - allEntries.count
		selection.removeAll()
		applyFilterAndSort()
	}

	func clearSelection() {
		selection.removeAll()
	}

	func setMinimumUserCount(_ value: String) {
		let digits = value.filter(\.isNumber)
		guard digits.isEmpty == false, let count = UInt(digits) else {
			minimumUserCount = ""
			return
		}
		minimumUserCount = String(min(count, 999_999))
	}

	func listArguments(supportedTokens: [String]) -> String? {
		Self.listArguments(
			minimumUserCount: UInt(minimumUserCount) ?? 0,
			supportedTokens: supportedTokens
		)
	}

	static func listArguments(
		minimumUserCount: UInt,
		supportedTokens: [String]
	) -> String? {
		// Search includes topics. An ELIST name mask would discard matching
		// topics before the local search sees them, even after search is cleared.
		guard minimumUserCount > 0, supportedTokens.contains("U") else { return nil }
		return ">\(minimumUserCount - 1)"
	}

	/** Filters once typing pauses.

	 Every keystroke used to re-filter and re-sort the whole list, which is what
	 made searching a large network feel like the window had stopped. */
	private func scheduleFilter() {
		startFiltering(after: Self.filterDelay)
	}

	/// Starts computing a new snapshot without the typing debounce.
	func applyFilterAndSort() {
		startFiltering(after: .zero)
	}

	private func startFiltering(after delay: Duration) {
		filterTask?.cancel()
		isFiltering = true
		let entries = allEntries
		let query = searchString.trimmingCharacters(in: .whitespacesAndNewlines)
		let order = sortOrder
		filterTask = Task { [weak self] in
			do {
				if delay > .zero {
					try await Task.sleep(for: delay)
				}
				let result = try await ServerChannelListSnapshot.filtered(entries, query: query, order: order)
				try Task.checkCancellation()
				guard let self else { return }
				rows = result.rows
				selection.formIntersection(result.identifiers)
				isFiltering = false
				filterTask = nil
			} catch is CancellationError {
				// A replacement request or the window's teardown owns the state now.
			} catch {
				assertionFailure("Channel-list computation failed: \(error)")
			}
		}
	}
}

private nonisolated struct ServerChannelListSnapshot: Sendable { // nonisolated: value
	let rows: [ServerChannelListEntry]
	let identifiers: Set<ServerChannelListEntry.ID>

	@concurrent
	static func filtered(
		_ entries: [ServerChannelListEntry],
		query: String,
		order: [ServerChannelListComparator]
	) async throws -> Self {
		var rows = try entries.filter {
			try Task.checkCancellation()
			return $0.matches(query)
		}
		try rows.sort { lhs, rhs in
			try Task.checkCancellation()
			for comparator in order {
				let comparison = comparator.compare(lhs, rhs)
				if comparison != .orderedSame {
					return comparison == .orderedAscending
				}
			}
			return false
		}
		try Task.checkCancellation()
		return Self(rows: rows, identifiers: Set(rows.map(\.id)))
	}
}

/** The channel-list window, as the protocol layer reports to it.

 `Protocol/` must not depend on feature presentation, so it speaks to
 ``ClientChannelListPresenting`` and the application's scenes answer. A reply
 only ever reaches a list that is already open: opening one is the single path
 that makes a session and asks the server for a listing. */
extension ApplicationScenes: ClientChannelListPresenting {
	func openChannelList(for client: Client) {
		openServerChannelList(for: client)
	}

	func closeChannelList(for client: Client) {
		closeServerChannelList(for: client.uniqueIdentifier)
	}

	func channelListDidStart(for client: Client) {
		serverChannelList(for: client.uniqueIdentifier)?.receiveListStart()
	}

	func channelListDidReceive(channelNamed name: String, memberCount: UInt, topic: String?, for client: Client) {
		serverChannelList(for: client.uniqueIdentifier)?.addChannel(name, count: memberCount, topic: topic)
	}

	func channelListDidFinish(for client: Client) {
		serverChannelList(for: client.uniqueIdentifier)?.finishRefresh()
	}
}
