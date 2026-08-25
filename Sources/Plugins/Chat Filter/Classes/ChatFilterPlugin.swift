/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2015 - 2018 Codeux Software, LLC & respective contributors.
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

@objc(TPI_ChatFilterExtension)
final class ChatFilterPlugin: NSObject, THOPluginProtocol, NSTableViewDataSource, NSTableViewDelegate,
	@unchecked Sendable
{
	private static let defaultsKey = "Glasstual Chat Filter Extension -> Filters"
	private static let dragType = NSPasteboard.PasteboardType("filterTableDragToken")

	@IBOutlet private var preferencesPaneView: NSView!
	@IBOutlet private var filterAddMenu: NSMenu!
	@IBOutlet private var filterAddButton: NSButton!
	@IBOutlet private var filterRemoveButton: NSButton!
	@IBOutlet private var filterEditButton: NSButton!
	@IBOutlet private var filterTable: TVCBasicTableView!
	@IBOutlet var filterArrayController: NSArrayController!

	@objc private dynamic var atleastOneFilterExists = false
	private var activeChatFilterIndex = -1
	private var activeEditSheet: ChatFilterEditSheet?
	private var engine: ChatFilterEngine?
	private var defaultsObserver: NSObjectProtocol?
	private var isSaving = false

	private var bundle: Bundle {
		Bundle(for: Self.self)
	}

	private var defaults: TPCPreferencesUserDefaults {
		.shared()
	}

	@objc override init() {
		super.init()
	}

	func receivedCommand(
		_ command: String,
		withText text: String?,
		authoredBy author: IRCPrefix,
		destinedFor destination: IRCChannel?,
		on client: IRCClient,
		receivedAt: Date,
		referenceMessage: IRCMessage?
	) -> Bool {
		engine?.receivedCommand(command, text: text, author: author, destination: destination, client: client,
		                        receivedAt: receivedAt, referenceMessage: referenceMessage) ?? true
	}

	func receivedText(
		_ text: String,
		authoredBy author: IRCPrefix,
		destinedFor destination: IRCChannel?,
		as lineType: TVCLogLineType,
		on client: IRCClient,
		receivedAt: Date,
		wasEncrypted: Bool
	) -> Bool {
		engine?.receivedText(text, author: author, destination: destination, lineType: lineType, client: client,
		                     receivedAt: receivedAt, wasEncrypted: wasEncrypted) ?? true
	}

	func pluginLoadedIntoMemory() {
		DispatchQueue.main.syncIfNeeded {
			self.bundle.loadNibNamed("TPI_ChatFilterExtension", owner: self, topLevelObjects: nil)
		}
		activeChatFilterIndex = -1
		engine = ChatFilterEngine(parentObject: self)
		loadFilters()
		defaultsObserver = NotificationCenter.default.addObserver(
			forName: UserDefaults.didChangeNotification,
			object: defaults,
			queue: .main
		) { [weak self] _ in
			Task { @MainActor in self?.defaultsChanged() }
		}
	}

	func pluginWillBeUnloadedFromMemory() {
		if let defaultsObserver {
			NotificationCenter.default.removeObserver(defaultsObserver)
		}
		defaultsObserver = nil
		engine = nil
	}

	var pluginPreferencesPaneView: NSView {
		preferencesPaneView
	}

	var pluginPreferencesPaneMenuItemName: String {
		localized("jq1-6r")
	}

	override nonisolated func awakeFromNib() {
		MainActor.assumeIsolated {
			super.awakeFromNib()
			filterTable.registerForDraggedTypes([Self.dragType])
		}
	}

	private var filters: [ChatFilter] {
		filterArrayController.arrangedObjects as? [ChatFilter] ?? []
	}

	private func loadFilters() {
		filterArrayController.remove(contentsOf: filterArrayController.arrangedObjects as? [Any] ?? [])
		let configurations = defaults.array(forKey: Self.defaultsKey) as? [[String: Any]] ?? []
		for configuration in configurations {
			filterArrayController.addObject(ChatFilter(dictionary: configuration))
		}
		reloadFilterCount()
	}

	private func saveFilters() {
		isSaving = true
		defaults.set(filters.map(\.dictionaryValue), forKey: Self.defaultsKey)
		reloadFilterCount()
	}

	private func defaultsChanged() {
		if isSaving {
			isSaving = false
		} else {
			loadFilters(); engine?.reloadFilterActionPerforms()
		}
	}

	private func reloadFilterCount() {
		atleastOneFilterExists = !filters.isEmpty
	}

	@IBAction private func filterTableDoubleClicked(_ sender: Any?) {
		filterEdit(sender)
	}

	@IBAction private func filterAdd(_: Any?) {
		editFilter(nil, at: -1)
	}

	@IBAction private func filterRemove(_: Any?) {
		guard TDCAlert.modalAlert(
			withMessage: localized("dj6-fn"),
			title: localized("c0k-xj"),
			defaultButton: localized("jvu-m7"),
			alternateButton: localized("p5s-ff")
		), filterTable.selectedRow >= 0 else { return }
		filterArrayController.remove(atArrangedObjectIndex: filterTable.selectedRow)
		saveFilters()
	}

	@IBAction private func filterEdit(_: Any?) {
		let row = filterTable.selectedRow
		guard filters.indices.contains(row) else { return }
		editFilter(filters[row], at: row)
	}

	@MainActor
	private func editFilter(_ filter: ChatFilter?, at index: Int) {
		activeChatFilterIndex = index
		let sheet = ChatFilterEditSheet(filter: filter)
		sheet.delegate = self
		sheet.window = NSApp.keyWindow
		sheet.start()
		activeEditSheet = sheet
	}

	@objc(chatFilterEditFilterSheet:onOk:)
	func editSheet(_: ChatFilterEditSheet, accepted filter: ChatFilter) {
		let immutable = filter is MutableChatFilter ? filter.copy() as! ChatFilter : filter
		if activeChatFilterIndex < 0 {
			filterArrayController.addObject(immutable)
		} else {
			filterArrayController.insert(immutable, atArrangedObjectIndex: activeChatFilterIndex + 1)
			filterArrayController.remove(atArrangedObjectIndex: activeChatFilterIndex)
		}
		saveFilters()
		engine?.reloadFilterActionPerforms()
	}

	@objc(chatFilterEditFilterSheetWillClose:)
	func editSheetWillClose(_: ChatFilterEditSheet) {
		activeChatFilterIndex = -1
		activeEditSheet = nil
	}

	@IBAction private func filterDuplicate(_: Any?) {
		let row = filterTable.selectedRow
		guard filters.indices.contains(row), let copy = filters[row].mutableCopy() as? MutableChatFilter else { return }
		copy.filterTitle += " (Duplicate)"
		editFilter(copy.copy() as? ChatFilter, at: -1)
	}

	@IBAction private func filterExport(_: Any?) {
		let row = filterTable.selectedRow
		guard filters.indices.contains(row), let window = NSApp.keyWindow else { return }
		let filter = filters[row]
		let panel = NSSavePanel()
		panel.canCreateDirectories = true
		panel.nameFieldStringValue = "filter.plist"
		panel.beginSheetModal(for: window) { response in
			if response == .OK, let url = panel.url {
				_ = filter.write(to: url)
			}
		}
	}

	@IBAction private func filterImport(_: Any?) {
		guard let window = NSApp.keyWindow else { return }
		let panel = NSOpenPanel()
		panel.allowsMultipleSelection = false
		panel.canChooseDirectories = false
		panel.canChooseFiles = true
		panel.resolvesAliases = true
		panel.message = localized("i9c-s3")
		panel.prompt = localized("2tc-m7")
		panel.beginSheetModal(for: window) { [weak self] response in
			guard response == .OK, let self, let url = panel.url else { return }
			panel.orderOut(nil)
			guard let filter = ChatFilter(contentsOf: url) else {
				_ = TDCAlert.modalAlert(withMessage: "", title: localized("eqr-7t"),
				                        defaultButton: localized("ybz-7i"), alternateButton: nil)
				return
			}
			editFilter(filter, at: -1)
		}
	}

	@IBAction private func presentFilterAddMenu(_ sender: Any?) {
		guard let view = sender as? NSView else { return }
		filterAddMenu.popUp(positioning: nil, at: .zero, in: view)
	}

	func tableView(_: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
		let item = NSPasteboardItem()
		item.setString(String(row), forType: Self.dragType)
		return item
	}

	func tableView(
		_: NSTableView,
		validateDrop _: NSDraggingInfo,
		proposedRow _: Int,
		proposedDropOperation _: NSTableView.DropOperation
	) -> NSDragOperation {
		.generic
	}

	func tableView(
		_: NSTableView,
		acceptDrop info: NSDraggingInfo,
		row: Int,
		dropOperation _: NSTableView.DropOperation
	) -> Bool {
		guard let value = info.draggingPasteboard.string(forType: Self.dragType),
		      let source = Int(value) else { return false }
		guard filters.indices.contains(source) else { return false }
		let filter = filters[source]
		filterArrayController.remove(atArrangedObjectIndex: source)
		let destination = source < row ? max(0, row - 1) : row
		filterArrayController.insert(filter, atArrangedObjectIndex: destination)
		saveFilters()
		return true
	}

	private func localized(_ key: String) -> String {
		bundle.localizedString(forKey: key, value: key, table: "TPI_ChatFilterExtension")
	}
}

private extension DispatchQueue {
	func syncIfNeeded(_ work: () -> Void) {
		if Thread.isMainThread {
			work()
		} else {
			sync(execute: work)
		}
	}
}
