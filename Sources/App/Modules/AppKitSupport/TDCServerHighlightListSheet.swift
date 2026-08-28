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

@objc(TDCServerHighlightListSheet)
@MainActor
public final class ServerHighlightListSheet: SheetBase, TDCClientPrototype {
	@objc public private(set) var client: IRCClient!
	@objc public private(set) var clientId: String?

	@IBOutlet private var headerTitleTextField: NSTextField!
	@IBOutlet private var highlightListTable: BasicTableView!
	@IBOutlet private var highlightListController: NSArrayController!

	private var highlightEntries: [Any] {
		highlightListController.arrangedObjects as? [Any] ?? []
	}

	@objc(initWithClient:)
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
			NSSortDescriptor(key: "timeLogged", ascending: false, selector: #selector(NSDate.compare(_:))),
			NSSortDescriptor(
				key: "channelName",
				ascending: false,
				selector: #selector(NSString.caseInsensitiveCompare(_:))
			),
		]

		let headerTitle = String(format: headerTitleTextField.stringValue, client.networkNameAlt)
		headerTitleTextField.stringValue = headerTitle

		if client.cachedHighlights.isEmpty == false {
			addEntry(client.cachedHighlights)
		}
	}

	@objc public func start() {
		startSheet()
	}

	@objc(addEntry:)
	public func addEntry(_ newEntry: Any) {
		if let entries = newEntry as? [Any] {
			for entry in entries {
				addEntry(entry)
			}
		} else if var entry = newEntry as? HighlightLogEntry {
			if entry is MutableHighlightLogEntry {
				guard let copiedEntry = entry.copy() as? HighlightLogEntry else {
					return
				}

				entry = copiedEntry
			}

			highlightListController.addObject(entry)
		}
	}

	@IBAction private func onClearList(_: Any?) {
		highlightListController.content = nil
		client.clearCachedHighlights()
	}

	@objc private func highlightDoubleClicked(_: Any?) {
		let row = highlightListTable.clickedRow

		if row < 0 {
			return
		}

		guard let entryItem = highlightEntries[row] as? HighlightLogEntry else {
			return
		}

		guard let channel = entryItem.channel else {
			return
		}

		guard let viewController = channel.viewController else {
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

	@objc public func copy(_: Any?) {
		let selectedRows = highlightListTable.selectedRowIndexes

		if selectedRows.isEmpty {
			return
		}

		var stringToCopy = ""

		for index in selectedRows {
			guard let entryItem = highlightEntries[index] as? HighlightLogEntry else {
				continue
			}

			stringToCopy.append(entryItem.description)

			if index != selectedRows.last {
				stringToCopy.append("\n")
			}
		}

		NSPasteboard.general.clearContents()
		NSPasteboard.general.setString(stringToCopy, forType: .string)
	}

	@objc(
		tableView:viewForTableColumn:row:
	)
	public func tableView(
		_ tableView: NSTableView,
		viewFor tableColumn: NSTableColumn?,
		row _: Int
	) -> NSView? {
		tableView.makeView(withIdentifier: tableColumn!.identifier, owner: self)
	}

	@objc public func windowWillClose(_: Notification) {
		highlightListTable.dataSource = nil
		highlightListTable.delegate = nil

		let selector = NSSelectorFromString("serverHighlightListSheetWillClose:")
		if let delegate, delegate.responds(to: selector) {
			_ = delegate.perform(selector, with: self)
		}
	}
}
