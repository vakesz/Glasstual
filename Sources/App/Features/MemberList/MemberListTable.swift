// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
import SwiftUI

struct MemberListTable: NSViewRepresentable {
	let model: MemberList
	let revision: Int
	let selection: Set<User.ID>
	let followsProfileOnScroll: Bool
	let redirectTyping: (String) -> Void

	func makeCoordinator() -> MemberListTableController {
		MemberListTableController(model: model)
	}

	func makeNSView(context: Context) -> NSScrollView {
		context.coordinator.scrollView
	}

	func updateNSView(_: NSScrollView, context: Context) {
		context.coordinator.redirectTyping = redirectTyping
		context.coordinator.followsProfileOnScroll = followsProfileOnScroll
		context.coordinator.update(revision: revision, selection: selection)
	}

	static func dismantleNSView(_: NSScrollView, coordinator: MemberListTableController) {
		coordinator.stopObserving()
	}

	func sizeThatFits(_ proposal: ProposedViewSize, nsView _: NSScrollView, context _: Context) -> CGSize? {
		CGSize(width: proposal.width ?? MemberListLayout.idealWidth, height: proposal.height ?? 300)
	}
}

/// A native table owns pointer coordinates and list interaction, while every
/// member and every presentation decision remains on the feature's model.
final class MemberListTableController: NSObject, NSTableViewDataSource, NSTableViewDelegate {
	let model: MemberList
	let scrollView = NSScrollView()
	let tableView = MemberListNativeTable()
	private(set) var rows: [MemberListTableRow] = []
	private(set) var updateCount = 0
	private var indexes: [MemberListTableRow.Identity: Int] = [:]
	private var renderedRevision: Int?
	private var isUpdating = false
	private var previousScrollOrigin = NSPoint.zero
	private let notifications = NotificationSubscriptions()
	var followsProfileOnScroll = true
	var redirectTyping: (String) -> Void = { _ in }
	var performDoubleClick: () -> Void = { AppServices.delegate.menuController?.memberInMemberListDoubleClicked() }
	var sendFiles: ([String], String) -> Void = { paths, nickname in
		AppServices.delegate.menuController?.sendDroppedFiles(paths, nickname: nickname)
	}

	init(model: MemberList) {
		self.model = model
		super.init()
		let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("member"))
		column.resizingMask = .autoresizingMask
		tableView.addTableColumn(column)
		tableView.headerView = nil
		tableView.style = .inset
		tableView.backgroundColor = .clear
		tableView.autoresizingMask = [.width]
		tableView.allowsMultipleSelection = true
		tableView.allowsEmptySelection = true
		tableView.allowsColumnReordering = false
		tableView.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
		tableView.intercellSpacing = NSSize(width: 0, height: 2)
		tableView.rowHeight = MemberListLayout.avatarSize + 8
		tableView.dataSource = self
		tableView.delegate = self
		tableView.target = self
		tableView.doubleAction = #selector(doubleClicked)
		tableView.owner = self
		tableView.setAccessibilityLabel(String(localized: .MemberList.sectionMembers))
		tableView.setAccessibilityIdentifier("member-list")
		tableView.registerForDraggedTypes([.fileURL])
		scrollView.documentView = tableView
		scrollView.hasVerticalScroller = true
		scrollView.hasHorizontalScroller = false
		scrollView.autohidesScrollers = true
		scrollView.drawsBackground = false
		scrollView.contentView.postsBoundsChangedNotifications = true
		notifications.observe(NSView.boundsDidChangeNotification, object: scrollView.contentView) { [weak self] _ in
			self?.scrollPositionChanged()
		}
	}

	func stopObserving() {
		notifications.cancelAll()
	}

	func update(revision: Int, selection: Set<User.ID>) {
		isUpdating = true
		defer { isUpdating = false }
		if renderedRevision != revision {
			applyRows(MemberListTableRow.rows(in: model.groups))
			renderedRevision = revision
			updateCount += 1
		}
		let selectedIndexes = IndexSet(selection.compactMap { indexes[.member($0)] })
		if selectedIndexes != tableView.selectedRowIndexes {
			tableView.selectRowIndexes(selectedIndexes, byExtendingSelection: false)
		}
	}

	/// Inserts and removes identities without rebuilding the whole native list.
	/// Visible cells are refreshed for in-place user and appearance changes.
	private func applyRows(_ updated: [MemberListTableRow]) {
		let origin = scrollView.contentView.bounds.origin
		let topRow = tableView.row(at: origin)
		let anchor = rows.indices.contains(topRow) ? rows[topRow].id : nil
		let offset = topRow >= 0 ? origin.y - tableView.rect(ofRow: topRow).minY : 0
		let difference = updated.map(\.id).difference(from: rows.map(\.id))
		var removed = IndexSet()
		var inserted = IndexSet()
		for change in difference {
			switch change {
			case let .remove(index, _, _): removed.insert(index)
			case let .insert(index, _, _): inserted.insert(index)
			}
		}
		rows = updated
		indexes = Dictionary(uniqueKeysWithValues: rows.enumerated().map { ($0.element.id, $0.offset) })
		if difference.isEmpty == false {
			tableView.beginUpdates()
			tableView.removeRows(at: removed, withAnimation: [])
			tableView.insertRows(at: inserted, withAnimation: [])
			tableView.endUpdates()
		}
		tableView.enumerateAvailableRowViews { [self] rowView, index in
			guard rows.indices.contains(index) else { return }
			configure(rowView, at: index)
			if let cell = tableView.view(atColumn: 0, row: index, makeIfNecessary: false) as? MemberListTableCell {
				configure(cell, at: index)
			}
		}
		if let anchor, let index = indexes[anchor], difference.isEmpty == false {
			scrollView.contentView.scroll(to: NSPoint(x: origin.x, y: tableView.rect(ofRow: index).minY + offset))
			scrollView.reflectScrolledClipView(scrollView.contentView)
		}
		previousScrollOrigin = scrollView.contentView.bounds.origin
	}

	func numberOfRows(in _: NSTableView) -> Int {
		rows.count
	}

	func tableView(_: NSTableView, isGroupRow row: Int) -> Bool {
		rows.indices.contains(row) && rows[row].member == nil
	}

	func tableView(_: NSTableView, shouldSelectRow row: Int) -> Bool {
		member(at: row) != nil
	}

	func tableView(_: NSTableView, heightOfRow row: Int) -> CGFloat {
		member(at: row) == nil ? 26 : MemberListLayout.avatarSize + 8
	}

	func tableView(_ tableView: NSTableView, viewFor _: NSTableColumn?, row: Int) -> NSView? {
		let identifier = NSUserInterfaceItemIdentifier("member-cell")
		let cell = tableView.makeView(withIdentifier: identifier, owner: self) as? MemberListTableCell
			?? MemberListTableCell(frame: .zero)
		cell.identifier = identifier
		configure(cell, at: row)
		return cell
	}

	func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
		let identifier = NSUserInterfaceItemIdentifier("member-row")
		let view = tableView.makeView(withIdentifier: identifier, owner: self) as? MemberListTableRowView
			?? MemberListTableRowView(frame: .zero)
		view.identifier = identifier
		configure(view, at: row)
		return view
	}

	private func configure(_ cell: MemberListTableCell, at index: Int) {
		guard rows.indices.contains(index) else { return }
		cell.configure(row: rows[index], style: model.presentationStyle, overrides: model.nicknameColorOverrides)
	}

	private func configure(_ view: NSTableRowView, at index: Int) {
		guard rows.indices.contains(index), let view = view as? MemberListTableRowView else { return }
		let row = rows[index]
		view.configure(row: row, style: model.presentationStyle) { [weak model] in
			guard let member = row.member else { return }
			model?.showProfile(for: member.id)
		}
	}

	func tableViewSelectionDidChange(_: Notification) {
		guard isUpdating == false else { return }
		model.selectedMemberIDs = Set(tableView.selectedRowIndexes.compactMap { member(at: $0)?.id })
	}

	func member(at row: Int) -> Member? {
		guard rows.indices.contains(row) else { return nil }
		return rows[row].member
	}

	func row(for identifier: User.ID) -> Int? {
		indexes[.member(identifier)]
	}

	@objc private func doubleClicked() {
		activateMember(at: tableView.clickedRow)
	}

	func activateMember(at row: Int) {
		guard let member = member(at: row) else { return }
		model.hideProfile()
		model.notePrimaryInteraction(withID: member.id)
		performDoubleClick()
	}

	private func scrollPositionChanged() {
		let origin = scrollView.contentView.bounds.origin
		guard origin != previousScrollOrigin else { return }
		previousScrollOrigin = origin
		guard isUpdating == false, let window = tableView.window else { return }
		let point = tableView.convert(window.convertPoint(fromScreen: NSEvent.mouseLocation), from: nil)
		followProfile(at: point)
	}

	/// A single native row lookup; no layout preferences, scanning or selection.
	func followProfile(at point: NSPoint) {
		guard tableView.visibleRect.contains(point) else { return }
		let identifier = member(at: tableView.row(at: point))?.id
		model.followProfileWhileScrolling(over: identifier, enabled: followsProfileOnScroll)
	}
}

final class MemberListNativeTable: NSTableView {
	weak var owner: MemberListTableController?

	override func menu(for event: NSEvent) -> NSMenu? {
		owner?.contextMenu(at: row(at: convert(event.locationInWindow, from: nil)))
	}

	override func showContextMenuForSelection(_: Any?) {
		guard selectedRow >= 0, let menu = selectionContextMenu() else { return }
		scrollRowToVisible(selectedRow)
		let row = rect(ofRow: selectedRow)
		menu.popUp(positioning: nil, at: NSPoint(x: row.midX, y: row.maxY), in: self)
	}

	func selectionContextMenu() -> NSMenu? {
		owner?.contextMenu(at: selectedRow)
	}

	override func keyDown(with event: NSEvent) {
		if let text = TypingRedirect.text(
			for: event.characters ?? "",
			commandIsPressed: event.modifierFlags.contains(.command),
			controlIsPressed: event.modifierFlags.contains(.control)
		) {
			owner?.redirectTyping(text)
		} else {
			super.keyDown(with: event)
		}
	}
}
