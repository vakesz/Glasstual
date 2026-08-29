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

/// What `ServerHighlightListSheet` reports back.
@MainActor
public protocol ServerHighlightListSheetDelegate: AnyObject {
	func serverHighlightListSheetWillClose(_ sender: ServerHighlightListSheet)
}

/// How `ServerHighlightListSheet` orders its rows. The header cells still carry
/// the old sort-descriptor keys, which is what maps a click onto one of these.
private enum HighlightListSortKey: String {
	case timeLogged
	case channelName
}

@objc(TDCServerHighlightListSheet)
@MainActor
public final class ServerHighlightListSheet: SheetBase, NSWindowDelegate, TDCClientPrototype,
	TableViewPasteboardDelegate, NSTableViewDataSource, NSTableViewDelegate
{
	public private(set) var client: IRCClient!
	public private(set) var clientId: String?

	@IBOutlet private var headerTitleTextField: NSTextField!
	@IBOutlet private var highlightListTable: BasicTableView!

	/** The rows, in the order the table draws them.

	 A highlight is a value, so there is no `NSArrayController` to hold it and no
	 KVC key path to bind a column to: the sheet sorts the entries itself and
	 fills the cells in `tableView(_:viewFor:row:)`. */
	private var highlightEntries: [HighlightLogEntry] = []

	public init(client: IRCClient) {
		super.init(window: nil)
		self.client = client
		clientId = client.uniqueIdentifier
		prepareInitialState()
	}

	private func prepareInitialState() {
		Bundle.main.loadNibNamed("TDCServerHighlightListSheet", owner: self, topLevelObjects: nil)

		highlightListTable.doubleAction = #selector(highlightDoubleClicked(_:))
		highlightListTable.pasteboardDelegate = self
		highlightListTable.sortDescriptors = [
			NSSortDescriptor(key: HighlightListSortKey.timeLogged.rawValue, ascending: false),
		]

		let headerTitle = String(format: headerTitleTextField.stringValue, client.networkNameAlt)
		headerTitleTextField.stringValue = headerTitle

		addEntries(client.cachedHighlights)
	}

	public func start() {
		startSheet()
	}

	public func addEntry(_ newEntry: HighlightLogEntry) {
		addEntries([newEntry])
	}

	public func addEntries(_ newEntries: [HighlightLogEntry]) {
		guard newEntries.isEmpty == false else {
			return
		}

		highlightEntries.append(contentsOf: newEntries)
		sortAndReloadEntries()
	}

	/// Applies the table's current sort descriptors. `NSArrayController` used to
	/// do this; the comparisons are the ones its descriptors named.
	private func sortAndReloadEntries() {
		for descriptor in highlightListTable.sortDescriptors.reversed() {
			guard let key = descriptor.key.flatMap(HighlightListSortKey.init(rawValue:)) else {
				continue
			}

			highlightEntries.sort { first, second in
				let ordered = switch key {
				case .timeLogged:
					first.timeLogged < second.timeLogged
				case .channelName:
					first.channelName.localizedCaseInsensitiveCompare(second.channelName) == .orderedAscending
				}

				return descriptor.ascending ? ordered : !ordered
			}
		}

		highlightListTable.reloadData()
	}

	@IBAction private func onClearList(_: Any?) {
		highlightEntries = []
		highlightListTable.reloadData()
		client.clearCachedHighlights()
	}

	@objc private func highlightDoubleClicked(_: Any?) {
		let row = highlightListTable.clickedRow

		guard row >= 0, row < highlightEntries.count else {
			return
		}

		let entryItem = highlightEntries[row]

		guard let channel = entryItem.channel else {
			return
		}

		guard let viewController = channel.logController else {
			return
		}

		let channelId = channel.uniqueIdentifier
		guard let clientId else {
			return
		}

		viewController.jump(toLine: entryItem.lineNumber) { [weak self] (result: Bool) in
			guard result else {
				return
			}

			DispatchQueue.main.async {
				guard
					let channel = AppController.shared.world.findChannel(
						withId: channelId,
						onClientWithId: clientId
					)
				else {
					return
				}

				AppController.shared.mainWindow.select(channel)
				self?.cancel(nil)
			}
		}
	}

	public func copy(_: Any?) {
		let selectedRows = highlightListTable.selectedRowIndexes

		if selectedRows.isEmpty {
			return
		}

		var stringToCopy = ""

		for index in selectedRows where index < highlightEntries.count {
			stringToCopy.append(highlightEntries[index].description)

			if index != selectedRows.last {
				stringToCopy.append("\n")
			}
		}

		NSPasteboard.general.clearContents()
		NSPasteboard.general.setString(stringToCopy, forType: .string)
	}

	public func numberOfRows(in _: NSTableView) -> Int {
		highlightEntries.count
	}

	public func tableView(_ tableView: NSTableView, sortDescriptorsDidChange _: [NSSortDescriptor]) {
		guard tableView === highlightListTable else {
			return
		}

		sortAndReloadEntries()
	}

	public func tableView(
		_ tableView: NSTableView,
		viewFor tableColumn: NSTableColumn?,
		row: Int
	) -> NSView? {
		guard let tableColumn, row < highlightEntries.count else {
			return nil
		}

		let view = tableView.makeView(withIdentifier: tableColumn.identifier, owner: self)

		guard let cell = view as? NSTableCellView, let textField = cell.textField else {
			return view
		}

		let entry = highlightEntries[row]

		switch tableColumn.identifier.rawValue {
		case "channelName":
			textField.stringValue = entry.channelName
		case "renderedMessage":
			textField.attributedStringValue = entry.renderedMessage
		case "timeLogged":
			textField.stringValue = entry.timeLoggedFormatted
		default:
			break
		}

		return view
	}

	public func windowWillClose(_: Notification) {
		highlightListTable.dataSource = nil
		highlightListTable.delegate = nil

		(delegate as? any ServerHighlightListSheetDelegate)?.serverHighlightListSheetWillClose(self)
	}
}
