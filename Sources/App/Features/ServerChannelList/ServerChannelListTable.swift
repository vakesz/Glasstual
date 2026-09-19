// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
import SwiftUI

/// Keeps native row reuse and responder-chain commands inside the table. The
/// SwiftUI scene and model still own search, sorting, selection and networking.
struct ServerChannelListTable: NSViewRepresentable {
	let model: ServerChannelListModel
	let revision: Int
	let selection: Set<ServerChannelListEntry.ID>
	let sortOrder: [ServerChannelListComparator]
	let joinSelected: () -> Void

	func makeCoordinator() -> ServerChannelListTableController {
		ServerChannelListTableController(model: model)
	}

	func makeNSView(context: Context) -> NSScrollView {
		context.coordinator.scrollView
	}

	func updateNSView(_: NSScrollView, context: Context) {
		context.coordinator.joinSelected = joinSelected
		context.coordinator.update(revision: revision, selection: selection, sortOrder: sortOrder)
	}

	func sizeThatFits(_ proposal: ProposedViewSize, nsView _: NSScrollView, context _: Context) -> CGSize? {
		CGSize(width: proposal.width ?? 720, height: proposal.height ?? 320)
	}
}

final class ServerChannelListTableController: NSObject, NSTableViewDataSource, NSTableViewDelegate {
	let model: ServerChannelListModel
	let scrollView = NSScrollView()
	let tableView = ServerChannelListNativeTable()
	private(set) var rows: [ServerChannelListEntry] = []
	private(set) var reloadCount = 0
	var joinSelected: () -> Void = {}
	private var indexes: [ServerChannelListEntry.ID: Int] = [:]
	private var renderedRevision: Int?
	private var isUpdating = false
	private let topics = NSCache<NSUUID, NSAttributedString>()

	init(model: ServerChannelListModel) {
		self.model = model
		super.init()
		topics.countLimit = 512
		addColumn(.channelName, title: String(localized: .ServerChannelList.channelName), width: 150, minimum: 100)
		addColumn(.memberCount, title: String(localized: .ServerChannelList.memberCount), width: 90, minimum: 70)
		addColumn(.topic, title: String(localized: .ServerChannelList.topic), width: 420, minimum: 220)
		tableView.style = .inset
		tableView.rowHeight = 24
		tableView.usesAutomaticRowHeights = false
		tableView.autoresizingMask = [.width]
		tableView.allowsMultipleSelection = true
		tableView.allowsEmptySelection = true
		tableView.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
		tableView.dataSource = self
		tableView.delegate = self
		tableView.target = self
		tableView.doubleAction = #selector(doubleClicked)
		tableView.owner = self
		tableView.setAccessibilityLabel(String(localized: .ServerChannelList.publicChannelList))
		tableView.setAccessibilityIdentifier("server-channel-list")
		scrollView.documentView = tableView
		scrollView.hasVerticalScroller = true
		scrollView.hasHorizontalScroller = true
		scrollView.autohidesScrollers = true
	}

	private func addColumn(_ field: ServerChannelListComparator.Field, title: String, width: CGFloat, minimum: CGFloat) {
		let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(field.rawValue))
		column.title = title
		column.sortDescriptorPrototype = NSSortDescriptor(key: field.rawValue, ascending: true)
		// Keep the localized heading clear of the sort indicator, even after a
		// user narrows the column. A narrow window scrolls instead of clipping it.
		let headerMinimum = ceil(column.headerCell.cellSize.width + 24)
		column.minWidth = max(minimum, headerMinimum)
		column.width = max(width, column.minWidth)
		tableView.addTableColumn(column)
	}

	func update(revision: Int, selection: Set<ServerChannelListEntry.ID>, sortOrder: [ServerChannelListComparator]) {
		isUpdating = true
		defer { isUpdating = false }
		if renderedRevision != revision {
			let origin = scrollView.contentView.bounds.origin
			let topRow = tableView.row(at: origin)
			let anchor = rows.indices.contains(topRow) ? rows[topRow].id : nil
			let offset = topRow >= 0 ? origin.y - tableView.rect(ofRow: topRow).minY : 0
			rows = model.rows
			indexes = Dictionary(uniqueKeysWithValues: rows.enumerated().map { ($0.element.id, $0.offset) })
			tableView.reloadData()
			renderedRevision = revision
			reloadCount += 1
			if let anchor, let row = indexes[anchor] {
				scrollView.contentView.scroll(to: NSPoint(x: origin.x, y: tableView.rect(ofRow: row).minY + offset))
				scrollView.reflectScrolledClipView(scrollView.contentView)
			}
		}
		let selectedIndexes = IndexSet(selection.compactMap { indexes[$0] })
		if selectedIndexes != tableView.selectedRowIndexes {
			tableView.selectRowIndexes(selectedIndexes, byExtendingSelection: false)
		}
		let descriptors = sortOrder.map { NSSortDescriptor(key: $0.field.rawValue, ascending: $0.order == .forward) }
		if tableView.sortDescriptors != descriptors {
			tableView.sortDescriptors = descriptors
		}
	}

	func numberOfRows(in _: NSTableView) -> Int {
		rows.count
	}

	func tableView(_: NSTableView, typeSelectStringFor column: NSTableColumn?, row: Int) -> String? {
		guard rows.indices.contains(row), column?.identifier.rawValue == ServerChannelListComparator.Field.channelName.rawValue
		else { return nil }
		return rows[row].channelName
	}

	func tableView(_ tableView: NSTableView, viewFor column: NSTableColumn?, row: Int) -> NSView? {
		guard rows.indices.contains(row), let column,
		      let field = ServerChannelListComparator.Field(rawValue: column.identifier.rawValue) else { return nil }
		let cell = tableView.makeView(withIdentifier: column.identifier, owner: self) as? ServerChannelListTableCell
			?? ServerChannelListTableCell(frame: .zero)
		cell.identifier = column.identifier
		let entry = rows[row]
		switch field {
		case .channelName:
			cell.textField?.stringValue = entry.channelName
		case .memberCount:
			cell.textField?.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
			cell.textField?.stringValue = entry.memberCount.formatted()
		case .topic:
			cell.textField?.attributedStringValue = formattedTopic(for: entry)
			cell.topic = entry.unformattedTopic
		}
		return cell
	}

	private func formattedTopic(for entry: ServerChannelListEntry) -> NSAttributedString {
		let key = entry.id as NSUUID
		if let cached = topics.object(forKey: key) {
			return cached
		}
		let formatted = (entry.displayedTopic as NSString).attributedString(
			withIRCFormatting: NSFont.systemFont(ofSize: NSFont.systemFontSize),
			preferredFontColor: .controlTextColor
		) ?? NSAttributedString()
		topics.setObject(formatted, forKey: key)
		return formatted
	}

	func tableViewSelectionDidChange(_: Notification) {
		guard isUpdating == false else { return }
		model.selection = selectedIdentifiers
	}

	func tableView(_ tableView: NSTableView, sortDescriptorsDidChange _: [NSSortDescriptor]) {
		guard isUpdating == false else { return }
		model.sortOrder = tableView.sortDescriptors.compactMap { descriptor in
			guard let key = descriptor.key, let field = ServerChannelListComparator.Field(rawValue: key) else { return nil }
			return ServerChannelListComparator(field: field, order: descriptor.ascending ? .forward : .reverse)
		}
	}

	private var selectedIdentifiers: Set<ServerChannelListEntry.ID> {
		Set(tableView.selectedRowIndexes.compactMap { rows.indices.contains($0) ? rows[$0].id : nil })
	}

	func contextMenu(at row: Int) -> NSMenu? {
		guard rows.indices.contains(row) else { return nil }
		if tableView.selectedRowIndexes.contains(row) == false {
			tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
		}
		let menu = NSMenu()
		let item = NSMenuItem(title: String(localized: .ServerChannelList.joinSelectedChannels),
		                      action: #selector(joinSelection), keyEquivalent: "")
		item.target = self
		menu.addItem(item)
		return menu
	}

	@objc func joinSelection() {
		let identifiers = selectedIdentifiers
		guard identifiers.isEmpty == false else { return }
		model.selection = identifiers
		joinSelected()
	}

	@objc private func doubleClicked() {
		guard rows.indices.contains(tableView.clickedRow) else { return }
		joinSelection()
	}

	/// Copy is evaluated only for the command, never while scrolling, typing or
	/// changing selection in a large list.
	func copySelection(to pasteboard: NSPasteboard) {
		model.selection = selectedIdentifiers
		guard let text = model.selectedCopyItems.first else { return }
		pasteboard.clearContents()
		pasteboard.setString(text, forType: .string)
	}
}

final class ServerChannelListNativeTable: NSTableView {
	weak var owner: ServerChannelListTableController?

	override func menu(for event: NSEvent) -> NSMenu? {
		owner?.contextMenu(at: row(at: convert(event.locationInWindow, from: nil)))
	}

	override func keyDown(with event: NSEvent) {
		if event.modifierFlags.isDisjoint(with: [.command, .control, .option]),
		   event.charactersIgnoringModifiers == "\r" || event.charactersIgnoringModifiers == "\u{3}"
		{
			owner?.joinSelection()
		} else {
			super.keyDown(with: event)
		}
	}

	@objc func copy(_: Any?) {
		owner?.copySelection(to: .general)
	}

	override func validateUserInterfaceItem(_ item: any NSValidatedUserInterfaceItem) -> Bool {
		item.action == #selector(copy(_:)) ? selectedRowIndexes.isEmpty == false : super.validateUserInterfaceItem(item)
	}
}
