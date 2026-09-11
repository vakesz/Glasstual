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
 *********************************************************************** */

import Foundation
import Observation

struct ServerChannelListEntry: Identifiable, Hashable, Sendable {
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
		IRCFormattingParser.parse(unformattedTopic).string
	}

	var copyText: String {
		"\(channelName)\t\(memberCount)\t\(plainTopic)"
	}
}

struct ServerChannelListComparator: SortComparator {
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
	static let maximumSelectionCount = 8
	/** How many channels the window keeps.

	 A large network answers `LIST` with hundreds of thousands of rows, and
	 every one of them was kept, re-filtered and re-sorted on each keystroke.
	 What is past the cap is counted and reported, not silently dropped. */
	static let maximumEntryCount = 20000
	static let maximumDisplayedTopicLength = 200
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

	/// How many channels the server sent past the cap. Zero means the list is
	/// complete.
	private(set) var discardedEntryCount = 0

	private var allEntries: [ServerChannelListEntry] = []
	private var queuedEntries: [ServerChannelListEntry] = []
	@ObservationIgnored private var queuedWriteTask: Task<Void, Never>?
	@ObservationIgnored private var filterTask: Task<Void, Never>?

	/** What to tell the user when the list is not all of it, or `nil` when it is.

	 The count is what the window kept, not what the table is showing: the search
	 field narrows the rows further, and a notice that named the row count would
	 be wrong for as long as anything was typed into it. */
	var truncationNotice: String? {
		guard discardedEntryCount > 0 else { return nil }

		return ServerChannelListStrings.truncationNotice(keptChannelCount: allEntries.count)
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

		guard queuedWriteTask == nil else { return }

		queuedWriteTask = Task { [weak self] in
			try? await Task.sleep(for: .seconds(1))
			guard Task.isCancelled == false else { return }
			self?.flushQueuedEntries()
		}
	}

	func flushQueuedEntries() {
		queuedWriteTask?.cancel()
		queuedWriteTask = nil
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
		queuedWriteTask?.cancel()
		queuedWriteTask = nil
		filterTask?.cancel()
		filterTask = nil
		queuedEntries.removeAll()
		allEntries.removeAll()
		rows.removeAll()
		selection.removeAll()
		discardedEntryCount = 0
	}

	isolated deinit {
		queuedWriteTask?.cancel()
		filterTask?.cancel()
	}

	func cancelPendingWrites() {
		queuedWriteTask?.cancel()
		queuedWriteTask = nil
		queuedEntries.removeAll()
	}

	func replace(with entries: [ServerChannelListEntry]) {
		cancelPendingWrites()
		allEntries = Array(entries.prefix(Self.maximumEntryCount))
		discardedEntryCount = entries.count - allEntries.count
		selection.removeAll()
		applyFilterAndSort()
	}

	func limitSelection(from oldSelection: Set<ServerChannelListEntry.ID>) {
		guard selection.count > Self.maximumSelectionCount else { return }

		let proposedSelection = selection
		var allowed = oldSelection.intersection(proposedSelection)
		let remainingCapacity = Self.maximumSelectionCount - allowed.count
		if remainingCapacity > 0 {
			let additions = rows
				.compactMap { entry in
					proposedSelection.contains(entry.id) && allowed.contains(entry.id) == false ? entry.id : nil
				}
				.prefix(remainingCapacity)
			allowed.formUnion(additions)
		}
		selection = allowed
	}

	func selectOnly(_ id: ServerChannelListEntry.ID) {
		selection = [id]
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
			pattern: searchString,
			supportedTokens: supportedTokens
		)
	}

	static func listArguments(
		minimumUserCount: UInt,
		pattern: String?,
		supportedTokens: [String]
	) -> String? {
		var conditions: [String] = []

		if minimumUserCount > 0, supportedTokens.contains("U") {
			conditions.append(">\(minimumUserCount - 1)")
		}

		let trimmedPattern = pattern?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
		if trimmedPattern.isEmpty == false,
		   supportedTokens.contains("M"),
		   trimmedPattern.rangeOfCharacter(from: CharacterSet(charactersIn: ", ")) == nil
		{
			let patternValue = if trimmedPattern.contains("*") || trimmedPattern.contains("?") {
				trimmedPattern
			} else {
				"*\(trimmedPattern)*"
			}
			conditions.append(patternValue)
		}

		return conditions.isEmpty ? nil : conditions.joined(separator: ",")
	}

	/** Filters once typing pauses.

	 Every keystroke used to re-filter and re-sort the whole list, which is what
	 made searching a large network feel like the window had stopped. */
	private func scheduleFilter() {
		filterTask?.cancel()
		filterTask = Task { [weak self] in
			try? await Task.sleep(for: Self.filterDelay)
			guard Task.isCancelled == false else { return }
			self?.applyFilterAndSort()
		}
	}

	/// Filters now, for the callers that already have every row they are going
	/// to get — a finished refresh, a new sort order, the tests.
	func applyFilterAndSort() {
		filterTask?.cancel()
		filterTask = nil
		let query = searchString.trimmingCharacters(in: .whitespacesAndNewlines)
		rows = allEntries.filter { $0.matches(query) }
		rows.sort(using: sortOrder)
		selection.formIntersection(Set(rows.map(\.id)))
	}
}
