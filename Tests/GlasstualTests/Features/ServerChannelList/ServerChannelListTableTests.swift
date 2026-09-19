// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
@testable import Glasstual
import Testing

@MainActor
@Suite("Native server channel table", .serialized, .timeLimit(.minutes(1)))
struct ServerChannelListTableTests {
	@Test("A narrow window keeps column headings clear of their sort indicators")
	func headersFitAtTheirMinimumWidth() async {
		let fixture = await Fixture(count: 3)
		defer { fixture.window.close() }
		fixture.window.setContentSize(NSSize(width: 320, height: 320))
		fixture.window.contentView?.layoutSubtreeIfNeeded()
		let table = fixture.controller.tableView
		for column in table.tableColumns {
			let header = column.headerCell
			let bounds = NSRect(x: 0, y: 0, width: column.minWidth, height: header.cellSize.height)
			#expect(header.sortIndicatorRect(forBounds: bounds).minX >= header.cellSize.width)
			#expect(column.width >= column.minWidth)
			#expect(column.maxWidth >= column.minWidth)
		}
		#expect(fixture.controller.scrollView.hasHorizontalScroller)
		#expect(table.tableColumns.reduce(CGFloat.zero) { $0 + $1.minWidth } > fixture.controller.scrollView.bounds.width)
	}

	@Test("A large list realizes visible rows and selection changes never reload it")
	func largeListKeepsSelectionUpdatesBounded() async {
		let fixture = await Fixture(count: ServerChannelListModel.maximumEntryCount)
		defer { fixture.window.close() }
		let table = fixture.controller.tableView
		#expect(table.numberOfRows == ServerChannelListModel.maximumEntryCount)
		var availableRows = 0
		table.enumerateAvailableRowViews { _, _ in availableRows += 1 }
		#expect(availableRows > 0)
		#expect(availableRows < 100)
		let reloads = fixture.controller.reloadCount
		for index in 0 ..< 100 {
			fixture.model.selection = [fixture.model.rows[index].id]
			fixture.update()
		}
		#expect(fixture.controller.reloadCount == reloads)
		#expect(table.selectedRowIndexes == IndexSet(integer: 99))
	}

	@Test("Native column sorting preserves selection by identity")
	func sortingKeepsSelection() async {
		let fixture = await Fixture(count: 3)
		defer { fixture.window.close() }
		let table = fixture.controller.tableView
		table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
		let selected = fixture.model.selection
		#expect(selected == [fixture.model.rows[0].id])
		table.sortDescriptors = [NSSortDescriptor(key: "channelName", ascending: true)]
		await fixture.waitForRows()
		fixture.update()
		#expect(fixture.model.rows.map(\.channelName) == ["#channel0", "#channel1", "#channel2"])
		#expect(fixture.model.selection == selected)
		#expect(table.selectedRowIndexes == IndexSet(integer: 2))
	}

	@Test("A right click on empty space leaves selection alone; a row menu joins its selection")
	func contextMenuUsesValidRows() async throws {
		let fixture = await Fixture(count: 3)
		defer { fixture.window.close() }
		let table = fixture.controller.tableView
		table.selectRowIndexes(IndexSet([0, 1]), byExtendingSelection: false)
		let selection = fixture.model.selection
		#expect(fixture.controller.contextMenu(at: -1) == nil)
		#expect(fixture.controller.contextMenu(at: 3) == nil)
		#expect(fixture.model.selection == selection)
		#expect(fixture.controller.contextMenu(at: 0) != nil)
		#expect(fixture.model.selection == selection)
		let menu = try #require(fixture.controller.contextMenu(at: 2))
		var joined: [String] = []
		fixture.controller.joinSelected = { joined = fixture.model.selectedChannelNames }
		menu.performActionForItem(at: 0)
		#expect(joined == ["#channel0"])
		#expect(table.selectedRowIndexes == IndexSet(integer: 2))
	}

	@Test("Return joins the native selection and copy preserves full topics in visible order")
	func keyboardAndCopyKeepTheirContracts() async throws {
		let fixture = await Fixture(count: 3)
		defer { fixture.window.close() }
		let table = fixture.controller.tableView
		table.selectRowIndexes(IndexSet([0, 2]), byExtendingSelection: false)
		var joined: [String] = []
		fixture.controller.joinSelected = { joined = fixture.model.selectedChannelNames }
		let event = try #require(NSEvent.keyEvent(
			with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
			windowNumber: fixture.window.windowNumber, context: nil,
			characters: "\r", charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36
		))
		table.keyDown(with: event)
		#expect(joined == ["#channel2", "#channel0"])
		let pasteboard = NSPasteboard.withUniqueName()
		defer { pasteboard.releaseGlobally() }
		fixture.controller.copySelection(to: pasteboard)
		#expect(pasteboard.string(forType: .string) == fixture.model.selectedCopyItems.first)
		#expect(pasteboard.string(forType: .string)?.contains(Fixture.topic) == true)
	}

	@Test("Appending replies keeps selected identities and the row at the top of the viewport")
	func streamingRowsPreserveReadingPosition() async throws {
		let fixture = await Fixture(count: 200)
		defer { fixture.window.close() }
		let controller = fixture.controller
		let table = controller.tableView
		table.selectRowIndexes(IndexSet(integer: 100), byExtendingSelection: false)
		let selected = fixture.model.selection
		let origin = NSPoint(x: 0, y: table.rect(ofRow: 100).minY)
		controller.scrollView.contentView.scroll(to: origin)
		let top = table.row(at: controller.scrollView.contentView.bounds.origin)
		let anchor = try #require(controller.rows.indices.contains(top) ? controller.rows[top].id : nil)
		fixture.model.enqueue(channelName: "#new", memberCount: 1000, topic: nil)
		fixture.model.flushQueuedEntries()
		await fixture.waitForRows()
		fixture.update()
		let updatedTop = table.row(at: controller.scrollView.contentView.bounds.origin)
		#expect(controller.rows[updatedTop].id == anchor)
		#expect(fixture.model.selection == selected)
		#expect(table.selectedRowIndexes == IndexSet(integer: 101))
	}

	@Test("Topic cells defer the full tooltip and replace it when reused")
	func reusedTopicCellsKeepFullTooltipCurrent() {
		let cell = ServerChannelListTableCell(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
		cell.topic = "\u{2}Full topic\u{2} " + Fixture.topic
		#expect(cell.view(cell, stringForToolTip: 0, point: .zero, userData: nil) == "Full topic " + Fixture.topic)
		cell.topic = "\u{1f}New topic\u{1f}"
		#expect(cell.view(cell, stringForToolTip: 0, point: .zero, userData: nil) == "New topic")
	}

	private struct Fixture {
		static let topic = String(repeating: "Long topic ", count: 30)
		let model: ServerChannelListModel
		let controller: ServerChannelListTableController
		let window: NSWindow

		init(count: Int) async {
			model = ServerChannelListModel()
			for index in 0 ..< count {
				model.enqueue(channelName: "#channel\(index)", memberCount: UInt(index), topic: Self.topic)
			}
			model.finishRefresh()
			controller = ServerChannelListTableController(model: model)
			window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 720, height: 320),
			                  styleMask: .borderless, backing: .buffered, defer: false)
			window.isReleasedWhenClosed = false
			window.contentView = controller.scrollView
			await waitForRows()
			update()
			window.contentView?.layoutSubtreeIfNeeded()
		}

		func update() {
			controller.update(revision: model.rowsRevision, selection: model.selection, sortOrder: model.sortOrder)
		}

		func waitForRows() async {
			for await filtering in Observations({ model.isFiltering }) where filtering == false {
				return
			}
		}
	}
}
