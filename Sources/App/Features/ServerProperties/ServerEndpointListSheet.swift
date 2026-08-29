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
import CocoaExtensions
import Combine

private let endpointEntryTableDragToken = NSPasteboard.PasteboardType(
	"com.vakesz.glasstual.server-endpoint-list.table-row"
)

/// What `ServerEndpointListSheet` reports back. The endpoints are values, so
/// they cannot travel through `NSObject.perform(_:with:with:)`.
@MainActor
public protocol ServerEndpointListSheetDelegate: AnyObject {
	func serverEndpointListSheet(_ sender: ServerEndpointListSheet, onOk serverList: [Server])
	func serverEndpointListSheetWillClose(_ sender: ServerEndpointListSheet)
}

@objc(TDCServerEndpointListSheet)
@MainActor
public final class ServerEndpointListSheet: SheetBase {
	@IBOutlet private var entryTableController: NSArrayController!
	@IBOutlet private var entryTable: BasicTableView!
	@IBOutlet private var entryActionsSegmentedControl: NSSegmentedControl!

	private var canRemoveObservation: Task<Void, Never>?

	override public init(window: NSWindow?) {
		super.init(window: window)
		prepareInitialState()
	}

	private func prepareInitialState() {
		Bundle.main.loadNibNamed("TDCServerEndpointListSheet", owner: self, topLevelObjects: nil)

		entryTable.registerForDraggedTypes([endpointEntryTableDragToken])
		entryTable.draggingDestinationFeedbackStyle = .gap

		/* `observe`'s change handler is nonisolated and had to hop to reach the
		 segmented control anyway; awaiting the key path states the isolation
		 once and gives the sheet something it can cancel on close. */
		let controller: NSArrayController = entryTableController

		canRemoveObservation = Task { @MainActor [weak self] in
			for await _ in controller.publisher(for: \.canRemove, options: [.initial, .new]).bufferedValues {
				guard let self else {
					return
				}

				updateEntryActionsSegmentedControlEnabledState()
			}
		}
	}

	private var endpointDelegate: (any ServerEndpointListSheetDelegate)? {
		delegate as? any ServerEndpointListSheetDelegate
	}

	public func start(with serverList: [Server]) {
		for server in serverList {
			entryTableController.addObject(ServerEndpointListEntry(server: server))
		}

		startSheet()
	}

	@IBAction override public func ok(_ sender: Any?) {
		let serverListIn = entryTableController.arrangedObjects as? [Any] ?? []
		let serverListOut = serverListIn
			.compactMap { ($0 as? ServerEndpointListEntry)?.server }
			.filter { $0.serverAddress.isEmpty == false }

		endpointDelegate?.serverEndpointListSheet(self, onOk: serverListOut)

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
		entryTableController.addObject(ServerEndpointListEntry(server: Server()))

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
		entryTableController.remove(atArrangedObjectIndexes: selectedRows)
	}

	@objc public func windowWillClose(_: Notification) {
		canRemoveObservation?.cancel()
		canRemoveObservation = nil

		endpointDelegate?.serverEndpointListSheetWillClose(self)
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
