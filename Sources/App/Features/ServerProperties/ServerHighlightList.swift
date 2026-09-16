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

		let channel = ClientEnvironment.shared.clientDirectory?.findChannel(
			withId: entry.channelId,
			onClientWithId: entry.clientId
		)
		channelName = channel?.name ?? ApplicationStrings.unknownValue

		let line = entry.lineLogged
		let formattedMessage = if line.lineType == .action {
			String(localized: .Notifications.bodyActionWithNickname(line.nickname ?? "", line.messageBody))
		} else {
			String(
				localized: .Notifications.bodyMessageWithNickname(
					line.formattedNickname(in: channel) ?? "",
					line.messageBody
				)
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

	/// How long ago the highlight arrived, as of `now`. The table redraws
	/// this every minute.
	func timeLabel(relativeTo now: Date) -> String {
		Self.relativeTimeFormatter.localizedString(for: time, relativeTo: now)
	}

	private static let relativeTimeFormatter: RelativeDateTimeFormatter = {
		let formatter = RelativeDateTimeFormatter()
		formatter.dateTimeStyle = .numeric
		return formatter
	}()

	/** The row as the pasteboard gets it.

	 The time is written out in full. "5 minutes ago" is already wrong by the
	 time it is pasted anywhere, and the table used to put exactly that on the
	 pasteboard. */
	var copyText: String {
		"\(time.formatted(date: .abbreviated, time: .shortened))\t\(channelName)\t\(plainMessage)"
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

		return result.ordered(by: order)
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

/** One connection's logged highlights, as its own window.

 A modal sheet was the wrong shape for a list whose only purpose is to jump into
 the transcript: choosing a row had to dismiss the sheet to get there, and going
 back for the next one meant reopening it. The window stays up, the transcript
 moves behind it, and highlights logged while it is open are added as they
 arrive. */
@MainActor
@Observable
final class ServerHighlightList: ClientScoped {
	let client: Client
	let clientId: String?

	let model = ServerHighlightListModel()

	init(client: Client) {
		self.client = client
		clientId = client.uniqueIdentifier
		model.replace(with: client.cachedHighlights)
	}

	var networkName: String {
		client.networkNameAlt
	}

	func addEntry(_ newEntry: HighlightLogEntry) {
		model.addEntries([newEntry])
	}

	func clearHighlights() {
		model.clear()
		client.clearCachedHighlights()
	}

	/** Selects the channel the highlight was logged in and scrolls to the line.

	 The window stays open: the list exists to move around the transcript with,
	 and closing it on every jump made a second one a second trip through the
	 menu. The channel is looked up again once the jump lands because the wait
	 gives the world time to have destroyed it. */
	func activateHighlight(withID id: String) {
		guard let entry = model.entry(withID: id) else { return }
		let channel = ClientEnvironment.shared.clientDirectory?.findChannel(
			withId: entry.channelId,
			onClientWithId: entry.clientId
		)
		guard let channel, let transcriptController = channel.transcriptController, let clientId else { return }

		let channelId = channel.uniqueIdentifier
		transcriptController.jump(toLine: entry.lineNumber) { success in
			guard success else { return }
			guard let channel = ClientEnvironment.shared.clientDirectory?.findChannel(
				withId: channelId,
				onClientWithId: clientId
			) else { return }

			AppServices.delegate.mainWindow.select(channel)
		}
	}
}
