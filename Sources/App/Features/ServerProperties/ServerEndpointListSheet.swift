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

private let endpointEntryTableDragToken = NSPasteboard.PasteboardType(
	"com.vakesz.glasstual.server-endpoint-list.table-row"
)

private nonisolated enum ServerEndpointListSection: Hashable, Sendable { // nonisolated: value
	case entries
}

private typealias ServerEndpointListSnapshot =
	NSDiffableDataSourceSnapshot<ServerEndpointListSection, String>

/** The endpoint table's data source, drag and drop included.

 `NSTableViewDiffableDataSource` implements only the row-count half of
 `NSTableViewDataSource`, and a table asks its *data source* — not its delegate
 — where a drag may land, so both answers have to come from the one object. The
 three methods are `@objc` because they satisfy optional requirements of a
 protocol the superclass, not this class, declares, and Swift will not expose
 them to the runtime on its own.

 The class is `nonisolated` because the initializer it inherits is: a main-actor
 subclass cannot re-declare it. It holds no state, and each `@objc` entry point
 — every one of them called by AppKit on the main thread — hops back onto the
 main actor by declaration. The sheet is reached through the table's delegate
 rather than a stored reference, so there is nothing here for the two isolations
 to disagree about. */
private final nonisolated class ServerEndpointListDataSource: // nonisolated: xpc-shim
	NSTableViewDiffableDataSource<ServerEndpointListSection, String>
{
	@MainActor
	@objc
	func tableView(_: NSTableView, pasteboardWriterForRow row: Int) -> (any NSPasteboardWriting)? {
		let item = NSPasteboardItem()
		item.setString(String(row), forType: endpointEntryTableDragToken)

		return item
	}

	@MainActor
	@objc
	func tableView(
		_ tableView: NSTableView,
		validateDrop _: any NSDraggingInfo,
		proposedRow row: Int,
		proposedDropOperation _: NSTableView.DropOperation
	) -> NSDragOperation {
		tableView.setDropRow(row, dropOperation: .above)

		return .move
	}

	@MainActor
	@objc
	func tableView(
		_ tableView: NSTableView,
		acceptDrop info: any NSDraggingInfo,
		row: Int,
		dropOperation _: NSTableView.DropOperation
	) -> Bool {
		guard let sheet = tableView.delegate as? ServerEndpointListSheet else {
			return false
		}

		return sheet.acceptEntryDrop(info, atRow: row)
	}
}

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
	@IBOutlet private var entryTable: BasicTableView!
	@IBOutlet private var entryActionsSegmentedControl: NSSegmentedControl!

	/// The endpoints being edited. They used to be boxed in a reference type so
	/// that the cells could share one row through KVC; the cells are handed a
	/// value and hand an edit back now, so the values can stay values.
	private var entries: [Server] = []
	private var entryDataSource: ServerEndpointListDataSource?

	override public init(window: NSWindow?) {
		super.init(window: window)
		prepareInitialState()
	}

	private func prepareInitialState() {
		Bundle.main.loadNibNamed("TDCServerEndpointListSheet", owner: self, topLevelObjects: nil)

		let entryDataSource = makeDataSource()
		self.entryDataSource = entryDataSource
		entryTable.dataSource = entryDataSource
		entryTable.delegate = self

		entryTable.registerForDraggedTypes([endpointEntryTableDragToken])
		entryTable.draggingDestinationFeedbackStyle = .gap

		updateEntryActionsSegmentedControlEnabledState()
	}

	private func makeDataSource() -> ServerEndpointListDataSource {
		ServerEndpointListDataSource(tableView: entryTable) { [weak self] tableView, column, _, entryID in
			let view = tableView.makeView(withIdentifier: column.identifier, owner: self)

			guard let self,
			      let cell = view as? ServerEndpointListSheetTableCellView,
			      let entry = entry(withID: entryID)
			else {
				return view ?? NSView()
			}

			cell.configure(with: entry, delegate: self)

			return cell
		}
	}

	private var endpointDelegate: (any ServerEndpointListSheetDelegate)? {
		delegate as? any ServerEndpointListSheetDelegate
	}

	private func entry(withID id: String) -> Server? {
		entries.first { $0.uniqueIdentifier == id }
	}

	private func index(ofEntryWithID id: String) -> Int? {
		entries.firstIndex { $0.uniqueIdentifier == id }
	}

	public func start(with serverList: [Server]) {
		entries = serverList

		applyEntries()
		startSheet()
	}

	@IBAction override public func ok(_ sender: Any?) {
		let serverListOut = entries.filter { $0.serverAddress.isEmpty == false }

		endpointDelegate?.serverEndpointListSheet(self, onOk: serverListOut)

		super.ok(sender)
	}

	// MARK: - Table

	private func applyEntries() {
		guard let entryDataSource else {
			return
		}

		let selection = selectedEntryIDs

		var snapshot = ServerEndpointListSnapshot()
		snapshot.appendSections([.entries])
		snapshot.appendItems(entries.map(\.uniqueIdentifier), toSection: .entries)
		entryDataSource.apply(snapshot, animatingDifferences: false)

		restoreSelection(to: selection)
		updateEntryActionsSegmentedControlEnabledState()
	}

	private var selectedEntryIDs: [String] {
		guard let entryDataSource else {
			return []
		}

		return entryTable.selectedRowIndexes.compactMap { entryDataSource.itemIdentifier(forRow: $0) }
	}

	/// Applying a snapshot clears the selection, which is held by row; the
	/// endpoints that held it are looked up again afterwards.
	private func restoreSelection(to entryIDs: [String]) {
		guard let entryDataSource, entryIDs.isEmpty == false else {
			return
		}

		let rows = IndexSet(entryIDs.compactMap { entryDataSource.row(forItemIdentifier: $0) })

		guard rows != entryTable.selectedRowIndexes else {
			return
		}

		entryTable.selectRowIndexes(rows, byExtendingSelection: false)
	}

	/// Re-draws every visible cell from the endpoints.
	///
	/// An edit leaves the row identities alone, so the diff is empty and no cell
	/// is rebuilt — but ticking "connect securely" moves the port that a cell in
	/// another column draws, so the row has to be re-stamped by hand.
	private func refreshVisibleCells() {
		guard let entryDataSource else {
			return
		}

		let visible = entryTable.rows(in: entryTable.visibleRect)

		guard visible.length > 0 else {
			return
		}

		for row in visible.location ..< NSMaxRange(visible) {
			guard let id = entryDataSource.itemIdentifier(forRow: row), let entry = entry(withID: id) else {
				continue
			}

			for column in entryTable.tableColumns.indices {
				let view = entryTable.view(atColumn: column, row: row, makeIfNecessary: false)
				(view as? ServerEndpointListSheetTableCellView)?.refresh(with: entry)
			}
		}
	}

	func acceptEntryDrop(_ info: any NSDraggingInfo, atRow row: Int) -> Bool {
		guard
			let draggedRowString = info.draggingPasteboard.string(forType: endpointEntryTableDragToken),
			let draggedRowIndex = Int(draggedRowString),
			entries.indices.contains(draggedRowIndex)
		else {
			return false
		}

		/* `row` is a drop position, so it can be one past the last row. */
		let destination = min(row, entries.count - 1)

		guard entries.indices.contains(destination), draggedRowIndex != destination else {
			return false
		}

		entries.insert(entries.remove(at: draggedRowIndex), at: destination)
		applyEntries()

		return true
	}

	// MARK: - Actions

	private func updateEntryActionsSegmentedControlEnabledState() {
		entryActionsSegmentedControl?.setEnabled(entryTable.selectedRow >= 0, forSegment: 1)
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
		entries.append(Server())

		applyEntries()

		/* Editing has to start after the table has taken the new row, which the
		 apply above has only just told it about. */
		Task { @MainActor [weak self] in
			guard let self else {
				return
			}

			let rowSelection = entryTable.numberOfRows - 1

			guard rowSelection >= 0 else {
				return
			}

			entryTable.scrollRowToVisible(rowSelection)
			entryTable.editColumn(0, row: rowSelection, with: nil, select: true)
		}
	}

	private func removeSelectedEntry() {
		let removedIDs = Set(selectedEntryIDs)

		guard removedIDs.isEmpty == false else {
			return
		}

		entries.removeAll { removedIDs.contains($0.uniqueIdentifier) }

		applyEntries()
	}

	@objc public func windowWillClose(_: Notification) {
		endpointDelegate?.serverEndpointListSheetWillClose(self)
	}
}

// MARK: - Table delegate

extension ServerEndpointListSheet: NSTableViewDelegate {
	public func tableViewSelectionDidChange(_: Notification) {
		updateEntryActionsSegmentedControlEnabledState()
	}
}

// MARK: - Cell edits

extension ServerEndpointListSheet: ServerEndpointListCellDelegate {
	func endpointCell(_: ServerEndpointListSheetTableCellView, didEdit server: Server) {
		guard let index = index(ofEntryWithID: server.uniqueIdentifier) else {
			return
		}

		entries[index] = server

		refreshVisibleCells()
	}

	func endpointCell(
		_: ServerEndpointListSheetTableCellView,
		didRejectEditWith error: any Error
	) {
		guard let sheet else {
			return
		}

		NSAlert(error: error).beginSheetModal(for: sheet, completionHandler: nil)
	}
}
