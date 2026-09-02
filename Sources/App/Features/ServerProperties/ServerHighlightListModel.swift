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

import AppKit
import Foundation
import Observation

struct ServerHighlightListRow: Identifiable, Equatable {
	let id: String
	let entry: HighlightLogEntry
	let channelName: String
	let message: AttributedString
	let plainMessage: String
	let time: Date

	init(entry: HighlightLogEntry) {
		id = "\(entry.clientId):\(entry.channelId):\(entry.lineNumber)"
		self.entry = entry

		let channel = ClientEnvironment.shared.world?.findChannel(
			withId: entry.channelId,
			onClientWithId: entry.clientId
		)
		channelName = channel?.name ?? ApplicationStrings.unknownValue

		let line = entry.lineLogged
		let formattedMessage = if line.lineType == .action {
			NotificationStrings.actionBody(
				nickname: line.nickname ?? "",
				text: line.messageBody
			)
		} else {
			NotificationStrings.messageBody(
				formattedNickname: line.formattedNickname(in: channel) ?? "",
				text: line.messageBody
			)
		}
		let renderedMessage = (formattedMessage as NSString).attributedString(
			withIRCFormatting: NSFont.systemFont(ofSize: 13),
			preferredFontColor: .controlTextColor
		) ?? NSAttributedString(string: formattedMessage)
		message = AttributedString(renderedMessage)
		plainMessage = renderedMessage.string
		time = entry.timeLogged
	}

	/// How long ago the highlight arrived, read at the moment the row is drawn.
	/// Freezing it at construction left every row showing the age it had when it
	/// was added, so nothing in an open sheet ever grew older.
	var timeLabel: String {
		let formattedInterval = humanReadableTimeInterval(time.timeIntervalSinceNow, true, 0) as String? ?? ""

		return ApplicationStrings.relativeTime(formattedInterval)
	}

	var copyText: String {
		"\(timeLabel)\t\(channelName)\t\(plainMessage)"
	}
}

struct ServerHighlightListComparator: SortComparator {
	enum Field: Hashable, Sendable {
		case channel
		case time
	}

	let field: Field
	var order: SortOrder

	func compare(_ lhs: ServerHighlightListRow, _ rhs: ServerHighlightListRow) -> ComparisonResult {
		let result = switch field {
		case .channel:
			lhs.channelName.localizedCaseInsensitiveCompare(rhs.channelName)
		case .time:
			lhs.time.compare(rhs.time)
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
final class ServerHighlightListModel {
	var rows: [ServerHighlightListRow] = []
	var selection: Set<String> = []
	var sortOrder: [ServerHighlightListComparator] = [
		ServerHighlightListComparator(field: .time, order: .reverse),
	]

	var selectedCopyItems: [String] {
		let selectedRows = rows.filter { selection.contains($0.id) }
		guard selectedRows.isEmpty == false else { return [] }
		return [selectedRows.map(\.copyText).joined(separator: "\n")]
	}

	func replace(with entries: [HighlightLogEntry]) {
		rows = entries.map(ServerHighlightListRow.init)
		selection = []
		sort(using: sortOrder)
	}

	func addEntries(_ entries: [HighlightLogEntry]) {
		guard entries.isEmpty == false else { return }
		rows.append(contentsOf: entries.map(ServerHighlightListRow.init))
		sort(using: sortOrder)
	}

	func clear() {
		rows = []
		selection = []
	}

	func sort(using order: [ServerHighlightListComparator]) {
		rows.sort(using: order)
	}

	func entry(withID id: String) -> HighlightLogEntry? {
		rows.first { $0.id == id }?.entry
	}
}
