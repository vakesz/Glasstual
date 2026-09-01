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
import Observation
import SwiftUI

@MainActor
public protocol ServerHighlightListSheetDelegate: AnyObject {
	func serverHighlightListSheetWillClose(_ sender: ServerHighlightListSheet)
}

@MainActor
public final class ServerHighlightListSheet: SheetBase, NSWindowDelegate, TDCClientPrototype {
	private static let contentSize = NSSize(width: 760, height: 430)

	public private(set) var client: IRCClient!
	public private(set) var clientId: String?

	let model = ServerHighlightListModel()

	public init(client: IRCClient) {
		self.client = client
		clientId = client.uniqueIdentifier
		super.init(window: nil)
		installSheet()
		model.replace(with: client.cachedHighlights)
	}

	private func installSheet() {
		let rootView = ServerHighlightListView(
			model: model,
			networkName: client.networkNameAlt,
			activate: { [weak self] id in self?.activateHighlight(withID: id) },
			clear: { [weak self] in self?.clearHighlights() },
			close: { [weak self] in self?.cancel(nil) }
		)
		let hostedSheet = NSWindow(
			contentRect: NSRect(origin: .zero, size: Self.contentSize),
			styleMask: [.titled, .resizable, .fullSizeContentView],
			backing: .buffered,
			defer: false
		)

		hostedSheet.contentViewController = NSHostingController(rootView: rootView)
		hostedSheet.contentMinSize = NSSize(width: 620, height: 320)
		hostedSheet.delegate = self
		hostedSheet.isReleasedWhenClosed = false
		hostedSheet.isRestorable = false
		hostedSheet.tabbingMode = .disallowed
		hostedSheet.preventsApplicationTerminationWhenModal = false
		hostedSheet.autorecalculatesKeyViewLoop = true
		hostedSheet.title = ServerHighlightListStrings.windowTitle(networkName: client.networkNameAlt)
		sheet = hostedSheet
	}

	public func start() {
		startSheet()
	}

	public func addEntry(_ newEntry: HighlightLogEntry) {
		model.addEntries([newEntry])
	}

	public func addEntries(_ newEntries: [HighlightLogEntry]) {
		model.addEntries(newEntries)
	}

	private func clearHighlights() {
		model.clear()
		client.clearCachedHighlights()
	}

	private func activateHighlight(withID id: String) {
		guard let entry = model.entry(withID: id),
		      let channel = entry.channel,
		      let logController = channel.logController,
		      let clientId
		else { return }

		let channelId = channel.uniqueIdentifier
		logController.jump(toLine: entry.lineNumber) { [weak self] success in
			guard success else { return }
			guard let channel = ClientEnvironment.shared.world?.findChannel(
				withId: channelId,
				onClientWithId: clientId
			) else { return }

			AppController.shared.mainWindow.select(channel)
			self?.cancel(nil)
		}
	}

	public func windowWillClose(_: Notification) {
		(delegate as? any ServerHighlightListSheetDelegate)?.serverHighlightListSheetWillClose(self)
	}
}

struct ServerHighlightListRow: Identifiable, Equatable {
	let id: String
	let entry: HighlightLogEntry
	let channelName: String
	let message: AttributedString
	let plainMessage: String
	let time: Date
	let timeLabel: String

	init(entry: HighlightLogEntry) {
		id = "\(entry.clientId):\(entry.channelId):\(entry.lineNumber)"
		self.entry = entry
		channelName = entry.channelName
		let renderedMessage = entry.renderedMessage
		message = AttributedString(renderedMessage)
		plainMessage = renderedMessage.string
		time = entry.timeLogged
		timeLabel = entry.timeLoggedFormatted
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
