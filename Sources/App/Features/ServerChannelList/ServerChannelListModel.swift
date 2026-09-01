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

	private(set) var rows: [ServerChannelListEntry] = []
	var selection: Set<ServerChannelListEntry.ID> = []
	var searchString = "" {
		didSet { applyFilterAndSort() }
	}

	var minimumUserCount = ""
	var sortOrder: [ServerChannelListComparator] = [
		ServerChannelListComparator(field: .memberCount, order: .reverse),
	] {
		didSet { applyFilterAndSort() }
	}

	var isRefreshing = true

	private var allEntries: [ServerChannelListEntry] = []
	private var queuedEntries: [ServerChannelListEntry] = []
	private var queuedWriteTask: Task<Void, Never>?

	var selectedChannelNames: [String] {
		rows.filter { selection.contains($0.id) }.map(\.channelName)
	}

	var selectedCopyItems: [String] {
		let selectedRows = rows.filter { selection.contains($0.id) }
		guard selectedRows.isEmpty == false else { return [] }
		return [selectedRows.map(\.copyText).joined(separator: "\n")]
	}

	func enqueue(channelName: String, memberCount: UInt, topic: String?) {
		queuedEntries.append(ServerChannelListEntry(
			channelName: channelName,
			memberCount: Int(memberCount),
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
		queuedEntries.removeAll()
		allEntries.removeAll()
		rows.removeAll()
		selection.removeAll()
	}

	func cancelPendingWrites() {
		queuedWriteTask?.cancel()
		queuedWriteTask = nil
		queuedEntries.removeAll()
	}

	func replace(with entries: [ServerChannelListEntry]) {
		cancelPendingWrites()
		allEntries = entries
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

	private func applyFilterAndSort() {
		let query = searchString.trimmingCharacters(in: .whitespacesAndNewlines)
		rows = allEntries.filter { $0.matches(query) }
		rows.sort(using: sortOrder)
		selection.formIntersection(Set(rows.map(\.id)))
	}
}
