/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
 * Copyright (c) 2010 - 2019 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 *
 *  * Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 *  * Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 *  * Neither the name of Textual, "Codeux Software, LLC", nor the
 *    names of its contributors may be used to endorse or promote products
 *    derived from this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED. IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
 * FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
 * OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
 * LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
 * OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
 * SUCH DAMAGE.
 *
 *********************************************************************** */

import AppKit
import CocoaExtensions
import GlasstualPluginKit

nonisolated enum ServerPropertiesTableSection: Hashable, Sendable { // nonisolated: value
	case rows
}

/// A diffable data source that still answers the drag-and-drop questions.
///
/// `NSTableViewDiffableDataSource` implements only the row-count half of
/// `NSTableViewDataSource`, and a table asks its *data source* — not its
/// delegate — where a drag may land, so both answers have to come from the one
/// object. The three methods below are `@objc` because they satisfy optional
/// requirements of a protocol the superclass, not this class, declares, and
/// Swift will not expose them to the runtime on its own.
///
/// The class is `nonisolated` because the initializer it inherits is: a
/// main-actor subclass cannot re-declare it. It holds no state of its own, and
/// each `@objc` entry point — every one of them called by AppKit on the main
/// thread — hops back onto the main actor by declaration. The sheet is reached
/// through the table's delegate rather than a stored reference so that there is
/// nothing here for the two isolations to disagree about.
nonisolated class ServerPropertiesTableDataSource: // nonisolated: xpc-shim
	NSTableViewDiffableDataSource<ServerPropertiesTableSection, String> {
	@MainActor
	@objc
	func tableView(_: NSTableView, pasteboardWriterForRow row: Int) -> (any NSPasteboardWriting)? {
		let item = NSPasteboardItem()
		item.setString(String(row), forType: serverPropertiesTableDragToken)

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
		guard let sheet = tableView.delegate as? ServerPropertiesSheet else {
			return false
		}

		return sheet.acceptTableDrop(info, in: tableView, atRow: row)
	}
}

extension ServerPropertiesSheet: HighlightEntrySheetDelegate, ChannelPropertiesSheetDelegate {
	func configureTables() {
		addressBookTableDataSource = makeTableDataSource(for: addressBookTable)
		channelListTableDataSource = makeTableDataSource(for: channelListTable)
		highlightsTableDataSource = makeTableDataSource(for: highlightsTable)

		addressBookTable.dataSource = addressBookTableDataSource
		channelListTable.dataSource = channelListTableDataSource
		highlightsTable.dataSource = highlightsTableDataSource

		for table in [addressBookTable, channelListTable, highlightsTable] {
			table?.delegate = self
			table?.target = self
			table?.doubleAction = #selector(tableViewDoubleClicked(_:))
			table?.registerForDraggedTypes([serverPropertiesTableDragToken])
			table?.draggingDestinationFeedbackStyle = .gap
		}
	}

	private func makeTableDataSource(for table: BasicTableView) -> ServerPropertiesTableDataSource {
		let dataSource = ServerPropertiesTableDataSource(tableView: table) {
			[weak self] tableView, column, row, _ in
			self?.tableCell(in: tableView, column: column, row: row) ?? NSView()
		}
		return dataSource
	}

	/// The channel list draws only real channels; a private message carries a
	/// channel config too, and it has no business in this table.
	///
	/// This was an `NSPredicate(format: "type == 0")` on the array controller,
	/// which could never have worked: the configs are Swift structs, so the
	/// controller boxed them, and asking a box for `type` by key raises
	/// `NSUnknownKeyException`. Setting the predicate on a client that had any
	/// channel configured therefore threw on the way into the sheet.
	static func displayedChannels(in channelList: [ChannelConfig]) -> [ChannelConfig] {
		channelList.filter { $0.type == .channel }
	}

	var displayedChannelList: [ChannelConfig] {
		Self.displayedChannels(in: channelList)
	}

	func applyAddressBookList() {
		apply(addressBookList.map(\.uniqueIdentifier), to: addressBookTableDataSource)
		updateAddressBookPage()
	}

	func applyChannelList() {
		apply(displayedChannelList.map(\.uniqueIdentifier), to: channelListTableDataSource)
		updateChannelListPage()
	}

	func applyHighlightList() {
		apply(highlightList.map(\.uniqueIdentifier), to: highlightsTableDataSource)
		updateHighlightsPage()
	}

	private func apply(_ identifiers: [String], to dataSource: ServerPropertiesTableDataSource?) {
		guard let dataSource else {
			return
		}

		var snapshot = NSDiffableDataSourceSnapshot<ServerPropertiesTableSection, String>()
		snapshot.appendSections([.rows])
		snapshot.appendItems(identifiers, toSection: .rows)
		dataSource.apply(snapshot, animatingDifferences: false)
	}

	func populateEncodings() {
		primaryEncodingButton.removeAllItems()
		fallbackEncodingButton.removeAllItems()
		encodingList = String.Encoding.supportedEncodingsByTitle(favoringUTF8: false)
		var names = (encodingList as NSDictionary).sortedDictionaryKeys as? [String] ?? []
		let utf8Title = String.localizedName(of: .utf8)
		names.removeAll { $0 == utf8Title }
		addEncodingItem(titled: utf8Title)
		let favored = ["Unicode", "Western", "Central European"]
		populateEncodingPopup(names, preferredEncodings: favored, ignoreFavored: false)
		if Preferences.Internals.includeAdvancedEncodings.value {
			populateEncodingPopup(names, preferredEncodings: favored, ignoreFavored: true)
		}
	}

	private func populateEncodingPopup(
		_ encodings: [String],
		preferredEncodings: [String],
		ignoreFavored: Bool
	) {
		var previousPrefix: String?
		for encoding in encodings {
			guard let range = encoding.range(of: " (", range: encoding.startIndex ..< encoding.endIndex)
			else { continue }
			let prefix = String(encoding[..<range.lowerBound])
			let favored = preferredEncodings.contains(prefix)
			guard ignoreFavored ? !favored : favored else { continue }
			if prefix != previousPrefix {
				previousPrefix = prefix
				primaryEncodingButton.menu?.addItem(.separator())
				fallbackEncodingButton.menu?.addItem(.separator())
			}
			addEncodingItem(titled: encoding)
		}
	}

	/// Every item carries its numeric encoding in `tag`. Localized titles are
	/// not stable identity, and a title is missing altogether while the advanced
	/// encodings are hidden.
	private func addEncodingItem(titled title: String) {
		let tag = Int(encodingList[title]?.uintValue ?? 0)
		for button in [primaryEncodingButton, fallbackEncodingButton] {
			button?.addItem(withTitle: title)
			button?.lastItem?.tag = tag
		}
	}

	/// Selects `encoding`, adding an item for it when the menu does not carry
	/// one. Without that, a server configured with an advanced encoding shows
	/// UTF-8 and has its configuration rewritten on OK.
	func selectEncoding(_ encoding: UInt, in button: NSPopUpButton) {
		let tag = Int(encoding)
		if button.menu?.items.contains(where: { $0.tag == tag }) != true {
			guard let title = (encodingList as NSDictionary)
				.ce_firstKey(for: NSNumber(value: encoding)) as? String
			else { return }
			button.addItem(withTitle: title)
			button.lastItem?.tag = tag
		}
		button.selectItem(withTag: tag)
	}

	@IBAction private func toggleAdvancedEncodings(_: Any?) {
		let primary = UInt(max(primaryEncodingButton.selectedTag(), 0))
		let fallback = UInt(max(fallbackEncodingButton.selectedTag(), 0))
		populateEncodings()
		selectEncoding(primary == 0 ? String.Encoding.utf8.rawValue : primary, in: primaryEncodingButton)
		selectEncoding(fallback == 0 ? String.Encoding.isoLatin1.rawValue : fallback, in: fallbackEncodingButton)
	}

	func updateChannelListPage() {
		let enabled = channelListTable.selectedRow >= 0
		deleteChannelButton.isEnabled = enabled
		editChannelButton.isEnabled = enabled
	}

	private func unfilteredChannelIndex(identifier: String) -> Int? {
		channelList.firstIndex { $0.uniqueIdentifier == identifier }
	}

	private func storeChannelConfig(_ config: ChannelConfig) {
		if let index = unfilteredChannelIndex(identifier: config.uniqueIdentifier) {
			channelList[index] = config
		} else {
			channelList.append(config)
		}

		applyChannelList()
	}

	private func removeChannelConfig(_ config: ChannelConfig) {
		guard let index = unfilteredChannelIndex(identifier: config.uniqueIdentifier) else {
			return
		}

		channelList.remove(at: index)

		applyChannelList()
	}

	private func moveChannelConfig(_ config: ChannelConfig, above target: ChannelConfig?) {
		guard let from = unfilteredChannelIndex(identifier: config.uniqueIdentifier) else {
			return
		}

		/* The move is over the whole list, not the rows on screen, because a
		 private message sitting between two channels still holds a position. */
		let lastIndex = max(channelList.count - 1, 0)
		let to = min(
			target.flatMap { unfilteredChannelIndex(identifier: $0.uniqueIdentifier) } ?? lastIndex,
			lastIndex
		)

		guard from != to else {
			return
		}

		channelList.insert(channelList.remove(at: from), at: to)

		applyChannelList()
	}

	func updateHighlightsPage() {
		let enabled = highlightsTable.selectedRow >= 0
		deleteHighlightButton.isEnabled = enabled
		editHighlightButton.isEnabled = enabled
	}

	@IBAction private func addHighlight(_: Any?) {
		let controller = HighlightEntrySheet(config: nil, channels: channelList)
		controller.delegate = self
		controller.window = sheet
		controller.start()
		highlightSheet = controller
	}

	@IBAction private func editHighlight(_: Any?) {
		let row = highlightsTable.selectedRow
		guard highlightList.indices.contains(row) else { return }
		let controller = HighlightEntrySheet(config: highlightList[row], channels: channelList)
		controller.delegate = self
		controller.window = sheet
		controller.start()
		highlightSheet = controller
	}

	public func highlightEntrySheet(_: HighlightEntrySheet, didSave config: HighlightMatchCondition) {
		if let index = highlightList.firstIndex(where: { $0.uniqueIdentifier == config.uniqueIdentifier }) {
			highlightList[index] = config
		} else {
			highlightList.append(config)
		}

		applyHighlightList()
	}

	public func highlightEntrySheetDidClose(_: HighlightEntrySheet) {
		highlightSheet = nil
	}

	@IBAction private func deleteHighlight(_: Any?) {
		let row = highlightsTable.selectedRow

		guard highlightList.indices.contains(row) else {
			return
		}

		highlightList.remove(at: row)
		applyHighlightList()
		selectNearestRow(in: highlightsTable, previousRow: row, remainingCount: highlightList.count)
	}

	@IBAction private func addChannel(_: Any?) {
		let controller = ChannelPropertiesSheet(config: nil)
		controller.delegate = self
		controller.window = sheet
		controller.start()
		channelSheet = controller
	}

	@IBAction private func editChannel(_: Any?) {
		let row = channelListTable.selectedRow
		let displayed = displayedChannelList
		guard displayed.indices.contains(row) else { return }
		let controller = ChannelPropertiesSheet(config: displayed[row])
		controller.delegate = self
		controller.window = sheet
		controller.start()
		channelSheet = controller
	}

	public func channelPropertiesSheet(_: ChannelPropertiesSheet, onOk config: ChannelConfig) {
		storeChannelConfig(config)
	}

	public func channelPropertiesSheetWillClose(_: ChannelPropertiesSheet) {
		channelSheet = nil
	}

	@IBAction private func deleteChannel(_: Any?) {
		let row = channelListTable.selectedRow
		let displayed = displayedChannelList
		guard displayed.indices.contains(row) else { return }
		removeChannelConfig(displayed[row])
		selectNearestRow(
			in: channelListTable,
			previousRow: row,
			remainingCount: displayedChannelList.count
		)
	}

	func selectNearestRow(in table: BasicTableView, previousRow: Int, remainingCount: Int) {
		guard remainingCount > 0 else { return }
		table.selectItem(at: min(previousRow, remainingCount - 1))
	}

	@objc private func channelAutoJoinToggled(_ sender: NSButton) {
		let row = channelListTable.row(for: sender)
		let displayed = displayedChannelList
		guard displayed.indices.contains(row) else { return }

		var config = displayed[row]
		config.autoJoin = sender.state == .on
		storeChannelConfig(config)
	}

	@objc private func tableViewDoubleClicked(_ sender: Any?) {
		if sender as AnyObject === channelListTable {
			editChannel(sender)
		} else if sender as AnyObject === highlightsTable {
			editHighlight(sender)
		} else if sender as AnyObject === addressBookTable {
			editAddressBookEntry(sender)
		}
	}
}

extension ServerPropertiesSheet: NSTableViewDelegate {
	/// The view for one cell. The data source asks for this now — the delegate's
	/// `tableView(_:viewFor:row:)` is never consulted once a diffable data
	/// source is installed.
	func tableCell(in tableView: NSTableView, column: NSTableColumn, row: Int) -> NSView? {
		let cell = tableView.makeView(withIdentifier: column.identifier, owner: self) as? NSTableCellView
		let displayedChannels = displayedChannelList

		if tableView === channelListTable,
		   column.identifier.rawValue == "join",
		   displayedChannels.indices.contains(row)
		{
			let checkbox = cell?.subviews.first as? NSButton
			checkbox?.state = displayedChannels[row].autoJoin ? .on : .off
			checkbox?.target = self
			checkbox?.action = #selector(channelAutoJoinToggled(_:))
			return cell
		}

		cell?.textField?.stringValue = stringValue(for: tableView, column: column.identifier.rawValue, row: row) ?? ""
		return cell
	}

	private func stringValue(for tableView: NSTableView, column: String, row: Int) -> String? {
		if tableView === channelListTable {
			let displayed = displayedChannelList
			guard displayed.indices.contains(row) else {
				return nil
			}

			let config = displayed[row]
			if column == "name" {
				return config.channelName
			}
			if column == "pass" {
				return config.secretKey ?? ""
			}
		} else if tableView === highlightsTable, highlightList.indices.contains(row) {
			let config = highlightList[row]
			if column == "keyword" {
				return config.matchKeyword
			}
			if column == "channel" {
				if let identifier = config.matchChannelId,
				   let channel = channelList.first(where: { $0.uniqueIdentifier == identifier })
				{
					return channel.channelName
				}
				return ServerPropertiesStrings.Highlight.allChannels
			}
			if column == "type" {
				return ServerPropertiesStrings.Highlight.matchType(isExcluded: config.matchIsExcluded)
			}
		} else if tableView === addressBookTable, addressBookList.indices.contains(row) {
			let config = addressBookList[row]
			if column == "hostmask" {
				return config.hostmask
			}
			if column == "type" {
				return ServerPropertiesStrings.AddressBook.entryType(config.entryType)
			}
		}
		return nil
	}

	public func tableViewSelectionDidChange(_ notification: Notification) {
		guard let table = notification.object as? NSTableView else { return }
		if table === channelListTable {
			updateChannelListPage()
		} else if table === highlightsTable {
			updateHighlightsPage()
		} else if table === addressBookTable {
			updateAddressBookPage()
		}
	}

	/// Reorders the list behind `tableView`. Called by the table's data source,
	/// which is where a table asks about dropping.
	func acceptTableDrop(_ info: any NSDraggingInfo, in tableView: NSTableView, atRow row: Int) -> Bool {
		guard let value = info.draggingPasteboard.string(forType: serverPropertiesTableDragToken),
		      let draggedRow = Int(value),
		      draggedRow >= 0, draggedRow < tableView.numberOfRows
		else { return false }

		/* `row` is a drop position, so it can be one past the last row. Moving
		 to it would index out of range. */
		let destination = min(row, tableView.numberOfRows - 1)

		if tableView === channelListTable {
			let displayed = displayedChannelList
			guard displayed.indices.contains(draggedRow) else { return false }
			let target = displayed.indices.contains(destination) ? displayed[destination] : nil
			moveChannelConfig(displayed[draggedRow], above: target)
		} else if tableView === highlightsTable {
			move(&highlightList, from: draggedRow, to: destination)
			applyHighlightList()
		} else if tableView === addressBookTable {
			move(&addressBookList, from: draggedRow, to: destination)
			applyAddressBookList()
		}

		return true
	}

	private func move<Element>(_ list: inout [Element], from: Int, to: Int) {
		guard list.indices.contains(from), list.indices.contains(to), from != to else {
			return
		}

		list.insert(list.remove(at: from), at: to)
	}
}
