/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \\ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\\___/_/\\_\\__|\\__,_|\\__,_|_|
 *
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 *********************************************************************** */

import AppKit
import CocoaExtensions

private let endpointEntryTableDragToken = NSPasteboard.PasteboardType(
	"com.vakesz.glasstual.server-endpoint-list.table-row"
)

@objc(TDCServerEndpointListSheet)
@MainActor
public final class ServerEndpointListSheet: SheetBase {
	@IBOutlet private var entryTableController: NSArrayController!
	@IBOutlet private var entryTable: BasicTableView!
	@IBOutlet private var entryActionsSegmentedControl: NSSegmentedControl!

	private var canRemoveObservation: NSKeyValueObservation?

	override public init(window: NSWindow?) {
		super.init(window: window)
		prepareInitialState()
	}

	private func prepareInitialState() {
		Bundle.main.loadNibNamed("TDCServerEndpointListSheet", owner: self, topLevelObjects: nil)

		entryTable.registerForDraggedTypes([endpointEntryTableDragToken])
		entryTable.draggingDestinationFeedbackStyle = .gap

		canRemoveObservation = entryTableController.observe(\.canRemove, options: [
			.initial,
			.new,
		]) { [weak self] _, _ in
			Task { @MainActor [weak self] in
				self?.updateEntryActionsSegmentedControlEnabledState()
			}
		}
	}

	@objc(startWithServerList:)
	public func start(with serverList: [Server]) {
		for server in serverList {
			entryTableController.addObject(server.mutableCopy())
		}

		startSheet()
	}

	@IBAction override public func ok(_ sender: Any?) {
		let serverListIn = entryTableController.arrangedObjects as? [Any] ?? []
		var serverListOut: [Server] = []

		for case let server as MutableServer in serverListIn {
			if server.serverAddress.isEmpty {
				continue
			}

			guard let server = server.copy() as? Server else {
				assertionFailure("MutableServer.copy() must return Server")
				continue
			}

			serverListOut.append(server)
		}

		let selector = NSSelectorFromString("serverEndpointListSheet:onOk:")
		if let delegate, delegate.responds(to: selector) {
			_ = delegate.perform(selector, with: self, with: serverListOut)
		}

		super.ok(sender)
	}

	private func updateEntryActionsSegmentedControlEnabledState() {
		entryActionsSegmentedControl.setEnabled(entryTableController.canRemove, forSegment: 1)
	}

	@IBAction private func entryActionsSegmentedControlClicked(_ sender: NSSegmentedControl) {
		switch sender.selectedSegment {
		case 0:
			addEntry()
		case 1:
			removeSelectedEntry()
		default:
			break
		}
	}

	private func addEntry() {
		let newEntry = MutableServer()
		entryTableController.addObject(newEntry)

		DispatchQueue.main.async { [weak self] in
			guard let self else {
				return
			}

			let rowSelection = entryTable.numberOfRows - 1
			entryTable.scrollRowToVisible(rowSelection)
			entryTable.editColumn(0, row: rowSelection, with: nil, select: true)
		}
	}

	private func removeSelectedEntry() {
		let selectedRows = entryTable.selectedRowIndexes
		entryTableController.perform(NSSelectorFromString("removeObjectsAtArrangedObjectIndexes:"), with: selectedRows)
	}

	@objc public func windowWillClose(_: Notification) {
		canRemoveObservation?.invalidate()
		canRemoveObservation = nil

		let selector = NSSelectorFromString("serverEndpointListSheetWillClose:")
		if let delegate, delegate.responds(to: selector) {
			_ = delegate.perform(selector, with: self)
		}
	}
}

extension ServerEndpointListSheet: NSTableViewDataSource, NSTableViewDelegate {
	@objc(tableView:pasteboardWriterForRow:)
	public func tableView(_: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
		let item = NSPasteboardItem()
		item.setString(String(row), forType: endpointEntryTableDragToken)
		return item
	}

	@objc(
		tableView:validateDrop:proposedRow:proposedDropOperation:
	)
	public func tableView(
		_ tableView: NSTableView,
		validateDrop _: any NSDraggingInfo,
		proposedRow row: Int,
		proposedDropOperation _: NSTableView.DropOperation
	) -> NSDragOperation {
		tableView.setDropRow(row, dropOperation: .above)
		return .move
	}

	@objc(tableView:acceptDrop:row:dropOperation:)
	public func tableView(
		_: NSTableView,
		acceptDrop info: any NSDraggingInfo,
		row: Int,
		dropOperation _: NSTableView.DropOperation
	) -> Bool {
		guard
			let draggedRowString = info.draggingPasteboard.string(forType: endpointEntryTableDragToken),
			let draggedRowIndex = Int(draggedRowString)
		else {
			return false
		}

		entryTableController.textual_moveObject(atArrangedObjectIndex: UInt(draggedRowIndex), to: UInt(row))
		return true
	}
}
