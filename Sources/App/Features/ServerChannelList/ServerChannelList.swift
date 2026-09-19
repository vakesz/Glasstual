// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Combine
import Foundation
import Observation

/// Owns one server's public-channel list and connects its SwiftUI scene to the
/// IRC session. Window lifecycle and restoration belong to SwiftUI.
@MainActor
final class ServerChannelList {
	let session: ServerSession
	let model = ServerChannelListModel()

	/** How long a listing may go without a reply before the window stops
	 waiting for it.

	 `RPL_LISTEND` is the only reply that ends a listing, and plenty of paths
	 never send one: a server that throttles `LIST` answers with a notice or
	 an unlisted numeric, and a connection can go quiet without closing. The
	 limit counts from the last reply, so a network streaming a very long
	 listing is never cut off. */
	private let replyTimeout: TimeInterval
	private let clock: TimerClock
	private var replyDeadline: ContinuousClock.Instant?
	private lazy var replyWatchdog = SessionTimer(clock: clock) { [weak self] _ in
		self?.checkReplyDeadline()
	}

	private var connectionObservation: Task<Void, Never>?

	init(session: ServerSession, replyTimeout: TimeInterval = 60, clock: TimerClock = .continuous) {
		self.session = session
		self.replyTimeout = replyTimeout
		self.clock = clock
		observeConnection()
	}

	isolated deinit {
		replyWatchdog.stop()
		connectionObservation?.cancel()
	}

	var sessionIdentifier: String {
		session.uniqueIdentifier
	}

	var networkName: String {
		session.networkNameAlt
	}

	var supportsMinimumUserCount: Bool {
		session.supportInfo.extendedListSupportsToken("U")
	}

	var serverSideListArguments: String? {
		model.listArguments(supportedTokens: session.supportInfo.extendedListTokens)
	}

	/// Asks the server for a fresh listing. A session that is not logged in has
	/// nobody to ask, so the list does not wait for an answer.
	func beginRefresh() {
		model.beginRefresh()
		guard session.isLoggedIn else {
			finishRefresh()
			return
		}
		session.requestChannelList(withArguments: serverSideListArguments)
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
		replyDeadline = nil
		replyWatchdog.stop()
		model.finishRefresh()
	}

	func joinSelectedChannels() {
		let channelNames = model.selectedChannelNames
		guard channelNames.isEmpty == false else { return }
		session.joinUnlistedChannelsAndSelectBestMatch(channelNames)
		model.clearSelection()
	}

	func close() {
		replyDeadline = nil
		replyWatchdog.stop()
		connectionObservation?.cancel()
		connectionObservation = nil
		model.cancelPendingWrites()
	}

	/// A reply advances the deadline without creating another sleeping task.
	/// Large networks can deliver thousands of replies in a single burst.
	private func noteReply() {
		replyDeadline = clock.now().advanced(by: .seconds(replyTimeout))
		replyWatchdog.startIfIdle(replyTimeout)
	}

	private func checkReplyDeadline() {
		guard let replyDeadline else { return }
		let remaining = clock.now().duration(to: replyDeadline).components
		let interval = TimeInterval(remaining.seconds) + TimeInterval(remaining.attoseconds) / 1e18
		if interval > 0 {
			replyWatchdog.start(interval)
		} else {
			finishRefresh()
		}
	}

	/** A listing cannot outlive the registration it was asked on: the server
	 that would have finished it is gone.

	 The initial value is read too. The observation starts when its task first
	 runs, which can be after a logout that happened in the same turn as the
	 refresh; the value it starts from is what still catches that one. */
	private func observeConnection() {
		let observedSession = session
		connectionObservation = Task { [weak self] in
			for await isLoggedIn in observedSession.publisher(for: \.isLoggedIn, options: [.initial, .new]).bufferedValues {
				guard let self, !Task.isCancelled else { return }
				if isLoggedIn == false, model.isRefreshing {
					finishRefresh()
				}
			}
		}
	}
}

nonisolated struct ServerChannelListEntry: Identifiable, Hashable, Sendable {
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
		guard let end = topic.index(
			topic.startIndex,
			offsetBy: ServerChannelListModel.maximumDisplayedTopicLength,
			limitedBy: topic.endIndex
		), end < topic.endIndex else { return topic }

		return String(topic[..<end]) + "\u{2026}"
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

nonisolated struct ServerChannelListComparator: SortComparator {
	enum Field: String, Hashable, Sendable {
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

		return result.ordered(by: order)
	}
}

@Observable
final class ServerChannelListModel {
	/** How many channels the window keeps.

	 A large network answers `LIST` with hundreds of thousands of rows, and
	 every one of them was kept, re-filtered and re-sorted on each keystroke.
	 What is past the cap is counted and reported, not silently dropped. */
	static let maximumEntryCount = 20000
	nonisolated static let maximumDisplayedTopicLength = 200
	/// How long typing has to pause before the list is filtered again.
	static let filterDelay = Duration.milliseconds(120)

	private(set) var rows: [ServerChannelListEntry] = []
	/// Changes only when a filtered snapshot is published, never on selection
	/// or incoming replies still waiting for their batch.
	private(set) var rowsRevision = 0
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
		didSet {
			guard sortOrder != oldValue else { return }
			applyFilterAndSort()
		}
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
	@ObservationIgnored private lazy var queuedWriteTimer = SessionTimer { [weak self] _ in
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
		rowsRevision += 1
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
				rowsRevision += 1
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

private nonisolated struct ServerChannelListSnapshot: Sendable {
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

/** The channel-list windows that are open, one per connection, and the session's
 report into them.

 `Chat/` must not depend on feature presentation, so it speaks to
 ``ChannelListPresenting`` and this answers. A reply only ever reaches a
 list that is already open: opening one is the single path that makes a session
 and asks the server for a listing. */
@MainActor
final class ServerChannelListWindowSessions: ChannelListPresenting {
	private let scenes: ApplicationScenes
	private var sessions = SceneSessions<String, ServerChannelList>()

	init(scenes: ApplicationScenes = AppServices.scenes) {
		self.scenes = scenes
	}

	/** The channel list open for a session, if there is one.

	 Only a lookup. Protocol replies and the scene body both ask here, and a
	 lookup that made a missing list sent the server another `LIST` for every row
	 still arriving after the window closed. */
	func list(for sessionIdentifier: String) -> ServerChannelList? {
		sessions[sessionIdentifier]
	}

	/// The window has gone, so the session it was showing goes with it.
	func didClose(for sessionIdentifier: String) {
		sessions.close(sessionIdentifier)?.close()
	}

	func openChannelList(for session: ServerSession) {
		let sessionIdentifier = session.uniqueIdentifier
		sessions.open(sessionIdentifier) { ServerChannelList(session: session) }.beginRefresh()
		scenes.open(ApplicationSceneID.serverChannelList, value: sessionIdentifier)
	}

	func closeChannelList(for session: ServerSession) {
		let sessionIdentifier = session.uniqueIdentifier
		didClose(for: sessionIdentifier)
		scenes.dismiss(ApplicationSceneID.serverChannelList, value: sessionIdentifier)
	}

	func channelListDidStart(for session: ServerSession) {
		list(for: session.uniqueIdentifier)?.receiveListStart()
	}

	func channelListDidReceive(channelNamed name: String, memberCount: UInt, topic: String?, for session: ServerSession) {
		list(for: session.uniqueIdentifier)?.addChannel(name, count: memberCount, topic: topic)
	}

	func channelListDidFinish(for session: ServerSession) {
		list(for: session.uniqueIdentifier)?.finishRefresh()
	}
}
