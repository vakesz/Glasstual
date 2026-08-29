/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
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
import CocoaExtensions
import GlasstualPluginKit
import os

@objc(TPI_ChatFilterExtension)
final class ChatFilterPlugin: NSObject, GlasstualPlugin, PluginIncomingCommandHandling,
	PluginPreferencesProviding,
	PluginTextEventHandling, ChatFilterEditSheetDelegate, NSTableViewDataSource, NSTableViewDelegate
{
	private static let logger = Logger(
		subsystem: Bundle.main.bundleIdentifier ?? "Glasstual",
		category: "Extension['Chat Filter']"
	)

	private static let defaultsKey = "Glasstual Chat Filter Extension -> Filters"
	private static let dragType = NSPasteboard.PasteboardType("filterTableDragToken")

	@IBOutlet private var preferencesPaneView: NSView?
	@IBOutlet private var filterAddMenu: NSMenu!
	@IBOutlet private var filterAddButton: NSButton!
	@IBOutlet private var filterRemoveButton: NSButton!
	@IBOutlet private var filterEditButton: NSButton!
	@IBOutlet private var filterTable: NSTableView!
	@IBOutlet var filterArrayController: NSArrayController!

	private var atleastOneFilterExists = false
	private var activeChatFilterIndex = -1
	private var activeEditSheet: ChatFilterEditSheet?
	private var engine: ChatFilterEngine?
	private var defaultsObserver: NSObjectProtocol?
	private var isSaving = false
	private var host: PluginHostContext?

	private var bundle: Bundle {
		Bundle(for: Self.self)
	}

	private var defaults: UserDefaults {
		guard let host else {
			preconditionFailure("The plugin host must load Chat Filters before it is used")
		}
		return host.defaults
	}

	override init() {
		super.init()
	}

	func receivedCommand(_ event: PluginIncomingCommandEvent) -> Bool {
		engine?.receivedCommand(event) ?? true
	}

	func receivedText(_ event: PluginTextEvent) -> Bool {
		engine?.receivedText(event) ?? true
	}

	func pluginLoaded(using host: PluginHostContext) {
		self.host = host
		if bundle.loadNibNamed("TPI_ChatFilterExtension", owner: self, topLevelObjects: nil) {
			/* Registered here rather than in `awakeFromNib`, which AppKit calls
			 without actor isolation. */
			filterTable?.registerForDraggedTypes([Self.dragType])
		} else {
			Self.logger.error("Failed to load TPI_ChatFilterExtension.xib; the preferences pane is unavailable")
		}
		activeChatFilterIndex = -1
		engine = ChatFilterEngine(parentObject: self, host: host)
		loadFilters()
		defaultsObserver = NotificationCenter.default.addObserver(
			forName: UserDefaults.didChangeNotification,
			object: defaults,
			queue: .main
		) { [weak self] _ in
			// The queue is `.main`, but the callback signature is not isolated.
			Task { @MainActor in self?.defaultsChanged() }
		}
	}

	func pluginWillUnload() {
		if let defaultsObserver {
			NotificationCenter.default.removeObserver(defaultsObserver)
		}
		defaultsObserver = nil
		engine = nil
		host = nil
	}

	var pluginPreferencesPaneView: NSView? {
		preferencesPaneView
	}

	var pluginPreferencesPaneMenuItemName: String {
		String(localized: .TPIChatFilterExtension.preferencesPaneTitle)
	}

	private var filters: [ChatFilter] {
		filterArrayController.arrangedObjects as? [ChatFilter] ?? []
	}

	private func loadFilters() {
		filterArrayController.remove(contentsOf: filterArrayController.arrangedObjects as? [Any] ?? [])
		let configurations = [PropertyListValue](
			propertyList: defaults.array(forKey: Self.defaultsKey) ?? []
		) ?? []
		for configuration in configurations.compactMap(\.dictionary) {
			filterArrayController.addObject(ChatFilter(dictionary: configuration))
		}
		reloadFilterCount()
	}

	private func saveFilters() {
		isSaving = true
		defaults.set(filters.map(\.dictionaryValue.propertyListObject), forKey: Self.defaultsKey)
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

	@MainActor
	@IBAction private func filterTableDoubleClicked(_ sender: Any?) {
		filterEdit(sender)
	}

	@MainActor
	@IBAction private func filterAdd(_: Any?) {
		editFilter(nil, at: -1)
	}

	@MainActor
	@IBAction private func filterRemove(_: Any?) {
		guard ChatFilterAlert.confirm(
			message: String(localized: .TPIChatFilterExtension.deleteFilterMessage),
			title: String(localized: .TPIChatFilterExtension.deleteFilterTitle),
			defaultButton: String(localized: .TPIChatFilterExtension.yesButton),
			alternateButton: String(localized: .TPIChatFilterExtension.noButton)
		), filterTable.selectedRow >= 0 else { return }
		filterArrayController.remove(atArrangedObjectIndex: filterTable.selectedRow)
		saveFilters()
	}

	@MainActor
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

	@MainActor
	func chatFilterEditSheet(_: ChatFilterEditSheet, accepted filter: ChatFilter) {
		let immutable: ChatFilter = if filter is MutableChatFilter, let immutableCopy = filter.copy() as? ChatFilter {
			immutableCopy
		} else {
			filter
		}
		if activeChatFilterIndex < 0 {
			filterArrayController.addObject(immutable)
		} else {
			filterArrayController.insert(immutable, atArrangedObjectIndex: activeChatFilterIndex + 1)
			filterArrayController.remove(atArrangedObjectIndex: activeChatFilterIndex)
		}
		saveFilters()
		engine?.reloadFilterActionPerforms()
	}

	@MainActor
	func chatFilterEditSheetWillClose(_: ChatFilterEditSheet) {
		activeChatFilterIndex = -1
		activeEditSheet = nil
	}

	@MainActor
	@IBAction private func filterDuplicate(_: Any?) {
		let row = filterTable.selectedRow
		guard filters.indices.contains(row), let copy = filters[row].mutableCopy() as? MutableChatFilter else { return }
		copy.filterTitle += " (Duplicate)"
		editFilter(copy.copy() as? ChatFilter, at: -1)
	}

	@MainActor
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

	@MainActor
	@IBAction private func filterImport(_: Any?) {
		guard let window = NSApp.keyWindow else { return }
		let panel = NSOpenPanel()
		panel.allowsMultipleSelection = false
		panel.canChooseDirectories = false
		panel.canChooseFiles = true
		panel.resolvesAliases = true
		panel.message = String(localized: .TPIChatFilterExtension.importPanelMessage)
		panel.prompt = String(localized: .TPIChatFilterExtension.selectButton)
		panel.beginSheetModal(for: window) { [weak self] response in
			guard response == .OK, let self, let url = panel.url else { return }
			panel.orderOut(nil)
			guard let filter = ChatFilter(contentsOf: url) else {
				ChatFilterAlert.inform(
					message: "",
					title: String(localized: .TPIChatFilterExtension.unreadableConfigurationTitle),
					dismissButton: String(localized: .TPIChatFilterExtension.okButton)
				)
				return
			}
			editFilter(filter, at: -1)
		}
	}

	@MainActor
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
}
