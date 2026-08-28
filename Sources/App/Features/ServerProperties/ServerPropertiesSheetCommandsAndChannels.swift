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

extension ServerPropertiesSheet: HighlightEntrySheetDelegate, ChannelPropertiesSheetDelegate {
	func configureTables() {
		for table in [addressBookTable, channelListTable, highlightsTable] {
			table?.target = self
			table?.doubleAction = #selector(tableViewDoubleClicked(_:))
			table?.registerForDraggedTypes([serverPropertiesTableDragToken])
			table?.draggingDestinationFeedbackStyle = .gap
		}
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

	func clearChannelListPredicate() {
		channelListArrayController.filterPredicate = nil
	}

	func setChannelListPredicate() {
		channelListArrayController.filterPredicate = NSPredicate(format: "type == 0")
	}

	private func unfilteredChannelIndex(identifier: String) -> Int? {
		let all = channelListArrayController.arrangedObjects as? [ChannelConfig] ?? []
		return all.firstIndex { $0.uniqueIdentifier == identifier }
	}

	private func storeChannelConfig(_ config: ChannelConfig) {
		clearChannelListPredicate()
		if let index = unfilteredChannelIndex(identifier: config.uniqueIdentifier) {
			channelListArrayController.textual_replaceObject(atArrangedObjectIndex: UInt(index), with: config)
		} else {
			channelListArrayController.addObject(config)
		}
		setChannelListPredicate()
	}

	private func removeChannelConfig(_ config: ChannelConfig) {
		clearChannelListPredicate()
		if let index = unfilteredChannelIndex(identifier: config.uniqueIdentifier) {
			channelListArrayController.removeObject(UInt(index))
		}
		setChannelListPredicate()
	}

	private func moveChannelConfig(_ config: ChannelConfig, above target: ChannelConfig?) {
		clearChannelListPredicate()
		guard let from = unfilteredChannelIndex(identifier: config.uniqueIdentifier) else {
			setChannelListPredicate()
			return
		}
		let count = (channelListArrayController.arrangedObjects as? [Any])?.count ?? 0
		/* A drop past the last row proposes `count`, which is one past the end;
		 the destination has to be an index that exists. */
		let lastIndex = max(count - 1, 0)
		let to = min(target.flatMap { unfilteredChannelIndex(identifier: $0.uniqueIdentifier) } ?? lastIndex, lastIndex)
		if from != to {
			channelListArrayController.textual_moveObject(atArrangedObjectIndex: UInt(from), to: UInt(to))
		}
		setChannelListPredicate()
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
			highlightListArrayController.textual_replaceObject(atArrangedObjectIndex: UInt(index), with: config)
		} else {
			highlightListArrayController.addObject(config)
		}
	}

	public func highlightEntrySheetDidClose(_: HighlightEntrySheet) {
		highlightSheet = nil
	}

	@IBAction private func deleteHighlight(_: Any?) {
		removeSelectedRow(
			from: highlightsTable,
			controller: highlightListArrayController,
			remainingCount: { self.highlightList.count }
		)
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
		guard channelList.indices.contains(row) else { return }
		let controller = ChannelPropertiesSheet(config: channelList[row])
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
		guard channelList.indices.contains(row) else { return }
		removeChannelConfig(channelList[row])
		selectNearestRow(in: channelListTable, previousRow: row, remainingCount: channelList.count)
	}

	func removeSelectedRow(
		from table: BasicTableView,
		controller: NSArrayController,
		remainingCount: () -> Int
	) {
		let row = table.selectedRow
		guard row >= 0 else { return }
		controller.removeObject(UInt(row))
		selectNearestRow(in: table, previousRow: row, remainingCount: remainingCount())
	}

	private func selectNearestRow(in table: BasicTableView, previousRow: Int, remainingCount: Int) {
		guard remainingCount > 0 else { return }
		table.selectItem(at: min(previousRow, remainingCount - 1))
	}

	@objc private func channelAutoJoinToggled(_ sender: NSButton) {
		let row = channelListTable.row(for: sender)
		guard channelList.indices.contains(row) else { return }

		var config = channelList[row]
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

extension ServerPropertiesSheet: NSTableViewDataSource, NSTableViewDelegate {
	public func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
		guard let column = tableColumn else { return nil }
		let cell = tableView.makeView(withIdentifier: column.identifier, owner: self) as? NSTableCellView
		if tableView === channelListTable, column.identifier.rawValue == "join", channelList.indices.contains(row) {
			let checkbox = cell?.subviews.first as? NSButton
			checkbox?.state = channelList[row].autoJoin ? .on : .off
			checkbox?.target = self
			checkbox?.action = #selector(channelAutoJoinToggled(_:))
			return cell
		}
		cell?.textField?.stringValue = stringValue(for: tableView, column: column.identifier.rawValue, row: row) ?? ""
		return cell
	}

	private func stringValue(for tableView: NSTableView, column: String, row: Int) -> String? {
		if tableView === channelListTable, channelList.indices.contains(row) {
			let config = channelList[row]
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

	public func tableView(_: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
		let item = NSPasteboardItem()
		item.setString(String(row), forType: serverPropertiesTableDragToken)
		return item
	}

	public func tableView(
		_ tableView: NSTableView,
		validateDrop _: any NSDraggingInfo,
		proposedRow row: Int,
		proposedDropOperation _: NSTableView.DropOperation
	) -> NSDragOperation {
		tableView.setDropRow(row, dropOperation: .above)
		return .move
	}

	public func tableView(
		_ tableView: NSTableView,
		acceptDrop info: any NSDraggingInfo,
		row: Int,
		dropOperation _: NSTableView.DropOperation
	) -> Bool {
		guard let value = info.draggingPasteboard.string(forType: serverPropertiesTableDragToken),
		      let draggedRow = Int(value),
		      draggedRow >= 0, draggedRow < tableView.numberOfRows
		else { return false }

		/* `row` is a drop position, so it can be one past the last row. Moving
		 to it would index out of range. */
		let destination = min(row, tableView.numberOfRows - 1)

		if tableView === channelListTable, channelList.indices.contains(draggedRow) {
			let target = channelList.indices.contains(destination) ? channelList[destination] : nil
			moveChannelConfig(channelList[draggedRow], above: target)
		} else if tableView === highlightsTable {
			highlightListArrayController.textual_moveObject(
				atArrangedObjectIndex: UInt(draggedRow),
				to: UInt(destination)
			)
		} else if tableView === addressBookTable {
			addressBookArrayController.textual_moveObject(
				atArrangedObjectIndex: UInt(draggedRow),
				to: UInt(destination)
			)
		}
		return true
	}
}
