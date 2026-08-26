/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
 * Copyright (c) 2010 - 2020 Codeux Software, LLC & respective contributors.
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
import os
import QuickLookUI

public typealias TDCFileTransferDialog = FileTransferDialog

private enum FileTransferDialogConstants {
	static let receiverHardLimit = 120
	static let quickLookMenuTag = 3007
	static let shareMenuTag = 3008
	static let revealMenuTag = 3006
	static let bookmarkKey = "File Transfers -> File Transfer Download Folder Bookmark"
	static let maintenanceInterval: TimeInterval = 1
}

private let fileTransferDialogLogger = Logger(
	subsystem: Bundle.main.bundleIdentifier ?? "Glasstual",
	category: "FileTransferDialog"
)

@objc(TDCFileTransferDialogWindow)
public final class FileTransferDialogWindow: NSWindow {
	override public nonisolated func acceptsPreviewPanelControl(_: QLPreviewPanel!) -> Bool {
		MainActor.assumeIsolated {
			delegate is FileTransferDialog
		}
	}

	override public nonisolated func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
		guard let panel else {
			return
		}

		MainActor.assumeIsolated {
			(delegate as? FileTransferDialog)?.beginPreviewPanelControlOnMainActor(panel)
		}
	}

	override public nonisolated func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
		guard let panel else {
			return
		}

		MainActor.assumeIsolated {
			(delegate as? FileTransferDialog)?.endPreviewPanelControlOnMainActor(panel)
		}
	}
}

@objc(TDCFileTransferDialog)
@MainActor
public final class FileTransferDialog: WindowBase,
	NSMenuItemValidation,
	NSMenuDelegate,
	NSTableViewDelegate,
	NSWindowDelegate,
	QLPreviewPanelDataSource,
	QLPreviewPanelDelegate,
	TLOInternetAddressLookupDelegate,
	@unchecked Sendable
{
	@IBOutlet private var clearButton: NSButton!
	@IBOutlet private var navigationControl: NSSegmentedControl!
	@IBOutlet public var fileTransferTable: BasicTableView!
	@IBOutlet private var fileTransfersController: NSArrayController!

	private var ipAddressRequest: InternetAddressLookup?
	private var maintenanceTimer: TimerImplementation?
	private var downloadDestinationURLPrivate: URL?
	private var keyDownEventMonitor: Any?
	private var previewItems: [URL] = []
	private var ipAddressCompletionBlocks: [(String?) -> Void] = []
	private var cachedIPAddress: String?

	override public init() {
		super.init()
		MainActor.assumeIsolated {
			prepareInitialState()
		}
	}

	private func prepareInitialState() {
		Bundle.main.loadNibNamed("TDCFileTransferDialog", owner: self, topLevelObjects: nil)
		fileTransferTable.style = NSTableView.Style.inset
		prepareTableMenu()
		installKeyDownEventMonitor()

		maintenanceTimer = TimerImplementation.timer(actionBlock: { [weak self] _ in
			MainActor.assumeIsolated {
				self?.onMaintenanceTimer()
			}
		}, onQueue: .main)

		NotificationCenter.default.addObserver(
			self,
			selector: #selector(clientWillBeDestroyed(_:)),
			name: Notification.Name("IRCWorldWillDestroyClientNotification"),
			object: nil
		)
	}

	isolated deinit {
		NotificationCenter.default.removeObserver(self)
		maintenanceTimer?.stop()
		removeKeyDownEventMonitor()
	}

	private func prepareTableMenu() {
		guard let menu = fileTransferTable.menu else {
			return
		}

		menu.delegate = self
		menu.item(withTag: FileTransferDialogConstants.quickLookMenuTag)?.image = menuItemImage(
			forSymbolNamed: "eye"
		)
		menu.item(withTag: FileTransferDialogConstants.revealMenuTag)?.image = menuItemImage(
			forSymbolNamed: "folder"
		)
	}

	private func menuItemImage(forSymbolNamed symbolName: String) -> NSImage? {
		let configuration = NSImage.SymbolConfiguration(
			pointSize: NSFont.systemFontSize,
			weight: .regular,
			scale: .medium
		)
		return NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
			.withSymbolConfiguration(configuration)
	}

	private func installKeyDownEventMonitor() {
		keyDownEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
			guard let self else {
				return event
			}

			guard keyDownEventTogglesQuickLook(event) else {
				return event
			}

			toggleQuickLookPanel()
			return nil
		}
	}

	private func removeKeyDownEventMonitor() {
		guard let keyDownEventMonitor else {
			return
		}

		NSEvent.removeMonitor(keyDownEventMonitor)
		self.keyDownEventMonitor = nil
	}

	private func keyDownEventTogglesQuickLook(_ event: NSEvent) -> Bool {
		guard event.window === window,
		      window.firstResponder === fileTransferTable as NSResponder,
		      event.modifierFlags.isDisjoint(with: .deviceIndependentFlagsMask),
		      event.charactersIgnoringModifiers == " "
		else {
			return false
		}

		return selectedFileTransfersWithLocalFiles.isEmpty == false
	}

	override public func show() {
		MainActor.assumeIsolated {
			show(true, restorePosition: true)
		}
	}

	@objc(show:)
	public func show(_ makeKeyWindow: Bool) {
		show(makeKeyWindow, restorePosition: true)
	}

	@objc(show:restorePosition:)
	public func show(_ makeKeyWindow: Bool, restorePosition: Bool) {
		if makeKeyWindow {
			window.makeKeyAndOrderFront(nil)
		} else {
			window.orderFront(nil)
		}

		if restorePosition {
			window.perform(NSSelectorFromString("restoreWindowStateForClass:"), with: type(of: self))
		}
	}

	// MARK: - Transfer lookup and lifecycle

	@objc(fileTransferMatchingPort:)
	public func fileTransfer(matchingPort port: UInt16) -> TDCFileTransferDialogTransferController? {
		firstFileTransfer { $0.hostPort == port }
	}

	@objc(fileTransferWithUniqueIdentifier:)
	public func fileTransfer(withUniqueIdentifier identifier: String) -> TDCFileTransferDialogTransferController? {
		firstFileTransfer { $0.uniqueIdentifier == identifier }
	}

	@objc(fileTransferExistsWithToken:)
	public func fileTransferExists(withToken transferToken: String) -> Bool {
		firstFileTransfer { $0.transferToken == transferToken } != nil
	}

	@objc(fileTransferSenderMatchingToken:)
	public func fileTransferSender(matchingToken transferToken: String) -> TDCFileTransferDialogTransferController? {
		firstFileTransfer { $0.transferToken == transferToken && $0.isSender }
	}

	@objc(fileTransferReceiverMatchingToken:)
	public func fileTransferReceiver(matchingToken transferToken: String) -> TDCFileTransferDialogTransferController? {
		firstFileTransfer { $0.transferToken == transferToken && $0.isSender == false }
	}

	@objc public func prepareForApplicationTermination() {
		downloadDestinationURLPrivate?.stopAccessingSecurityScopedResource()
		close()
		for fileTransfer in allFileTransfers {
			fileTransfer.perform(NSSelectorFromString("prepareForPermanentDestruction"))
		}
	}

	@objc(addReceiverForClient:nickname:address:port:filename:filesize:token:)
	public func addReceiver(
		for client: IRCClient,
		nickname: String,
		address hostAddress: String,
		port hostPort: UInt16,
		filename: String,
		filesize totalFilesize: UInt64,
		token transferToken: String?
	) -> String? {
		guard receiverCount <= FileTransferDialogConstants.receiverHardLimit else {
			fileTransferDialogLogger.error(
				"Maximum receiver count of \(FileTransferDialogConstants.receiverHardLimit, privacy: .public) exceeded"
			)
			return nil
		}

		guard let controller = TDCFileTransferDialogTransferController.receiver(
			for: client,
			nickname: nickname,
			address: hostAddress,
			port: hostPort,
			filename: filename,
			filesize: totalFilesize,
			token: transferToken
		) else {
			return nil
		}

		show(false, restorePosition: false)
		addFileTransfer(controller)

		if TPCPreferences.fileTransferRequestReplyAction() == .automaticallyDownload {
			controller.open(withPath: downloadDestinationURLPrivate?.path ?? TPCPathInfo.userDownloads)
		}

		return controller.uniqueIdentifier
	}

	@objc(addSenderForClient:nickname:path:autoOpen:)
	public func addSender(
		for client: IRCClient,
		nickname: String,
		path: String,
		autoOpen: Bool
	) -> String? {
		guard let controller = TDCFileTransferDialogTransferController.sender(
			for: client,
			nickname: nickname,
			path: path
		) else {
			return nil
		}

		show(true, restorePosition: false)
		addFileTransfer(controller)

		if autoOpen {
			controller.open()
		}

		return controller.uniqueIdentifier
	}

	@objc public func updateClearButton() {
		clearButton?.isEnabled = stoppedFileTransfers.isEmpty == false
	}

	private func addFileTransfer(_ controller: TDCFileTransferDialogTransferController) {
		let predicate = fileTransfersController.filterPredicate
		fileTransfersController.filterPredicate = nil
		fileTransfersController.insert(controller, atArrangedObjectIndex: 0)
		fileTransfersController.filterPredicate = predicate
	}

	private func removeFileTransfers(matching client: IRCClient) {
		let transfers = fileTransfers { $0.client === client }
		guard transfers.isEmpty == false else {
			return
		}

		prepareForPermanentDestruction(transfers)
		fileTransfersController.remove(contentsOf: transfers)
	}

	@objc private func clientWillBeDestroyed(_ notification: Notification) {
		guard let client = notification.object as? IRCClient else {
			return
		}

		removeFileTransfers(matching: client)
	}

	// MARK: - Menu validation and actions

	public func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
		let transfers = selectedFileTransfers
		guard transfers.isEmpty == false else {
			return false
		}

		switch menuItem.tag {
		case 3001:
			return transfers.contains { [.stopped, .recoverableError].contains($0.transferStatus) }
		case 3003:
			return transfers.contains { activeOrPendingStatuses.contains($0.transferStatus) }
		case 3004:
			return true
		case 3005, FileTransferDialogConstants.revealMenuTag:
			return transfers.contains(where: fileTransferHasLocalFile)
		case FileTransferDialogConstants.quickLookMenuTag, FileTransferDialogConstants.shareMenuTag:
			return transfers.allSatisfy(fileTransferHasLocalFile)
		default:
			return false
		}
	}

	private var activeOrPendingStatuses: Set<TDCFileTransferDialogTransferStatus> {
		[
			.connecting,
			.receiving,
			.isListeningAsSender,
			.isListeningAsReceiver,
			.sending,
			.mappingListeningPort,
			.waitingForLocalIPAddress,
			.waitingForReceiverToAccept,
			.waitingForResumeAccept,
		]
	}

	private func fileTransferHasLocalFile(_ fileTransfer: TDCFileTransferDialogTransferController) -> Bool {
		if fileTransfer.isSender == false, fileTransfer.transferStatus != .complete {
			return false
		}

		guard let filePath = fileTransfer.filePath else {
			return false
		}

		return FileManager.default.fileExists(atPath: filePath)
	}

	private var selectedFileTransfersWithLocalFiles: [TDCFileTransferDialogTransferController] {
		selectedFileTransfers.filter(fileTransferHasLocalFile)
	}

	private var selectedFileURLs: [URL] {
		selectedFileTransfersWithLocalFiles.compactMap(\.fileURL)
	}

	public func menuNeedsUpdate(_ menu: NSMenu) {
		guard let tableMenu = fileTransferTable.menu, menu === tableMenu else {
			return
		}

		let index = menu.indexOfItem(withTag: FileTransferDialogConstants.shareMenuTag)
		guard index >= 0 else {
			return
		}

		menu.removeItem(at: index)
		var items = selectedFileURLs
		if items.count != fileTransferTable.selectedRowIndexes.count {
			items = []
		}

		guard let shareItem = NSObject.masterController().menuController?.shareMenuItem(forItems: items) else {
			return
		}
		shareItem.tag = FileTransferDialogConstants.shareMenuTag
		menu.insertItem(shareItem, at: index)
	}

	@IBAction private func clear(_: Any?) {
		let transfers = stoppedFileTransfers
		prepareForPermanentDestruction(transfers)
		fileTransfersController.remove(contentsOf: transfers)
		updateClearButton()
	}

	@IBAction private func startTransferOfFile(_: Any?) {
		let savePath = downloadDestinationURLPrivate?.path
		var pending: [TDCFileTransferDialogTransferController] = []

		for transfer in selectedFileTransfers where [.stopped, .recoverableError].contains(transfer.transferStatus) {
			if transfer.isSender || transfer.path != nil {
				transfer.open()
			} else if let savePath {
				transfer.open(withPath: savePath)
			} else {
				pending.append(transfer)
			}
		}

		guard pending.isEmpty == false else {
			return
		}

		let panel = NSOpenPanel()
		panel.directoryURL = TPCPathInfo.userDownloadsURL
		panel.allowsMultipleSelection = false
		panel.canChooseDirectories = true
		panel.canChooseFiles = false
		panel.canCreateDirectories = true
		panel.resolvesAliases = true
		panel.message = LocalizedKey("TDCFileTransferDialog[dcm-w7]")
		panel.prompt = LocalizedKey("Prompts[xne-79]")
		panel.beginSheetModal(for: window) { response in
			guard response == .OK, let path = panel.url?.path else {
				return
			}

			for transfer in pending {
				transfer.open(withPath: path)
			}
		}
	}

	@IBAction private func stopTransferOfFile(_: Any?) {
		selectedFileTransfers.forEach { $0.closeAndPostNotification(false) }
	}

	@IBAction private func removeTransferFromList(_: Any?) {
		let transfers = selectedFileTransfers
		prepareForPermanentDestruction(transfers)
		fileTransfersController.remove(contentsOf: transfers)
	}

	@IBAction private func openReceivedFile(_: Any?) {
		selectedFileURLs.forEach { NSWorkspace.shared.open($0) }
	}

	@IBAction private func revealReceivedFileInFinder(_: Any?) {
		guard selectedFileURLs.isEmpty == false else {
			return
		}

		NSWorkspace.shared.activateFileViewerSelecting(selectedFileURLs)
	}

	@IBAction private func quickLookFile(_: Any?) {
		toggleQuickLookPanel()
	}

	@IBAction private func hideWindow(_: Any?) {
		close()
	}

	private func prepareForPermanentDestruction(_ transfers: [TDCFileTransferDialogTransferController]) {
		for transfer in transfers {
			transfer.perform(NSSelectorFromString("prepareForPermanentDestruction"))
		}
	}

	// MARK: - Quick Look

	private func toggleQuickLookPanel() {
		guard let panel = QLPreviewPanel.shared() else {
			return
		}

		if QLPreviewPanel.sharedPreviewPanelExists(),
		   panel.isVisible,
		   panel.currentController as AnyObject? === self
		{
			panel.orderOut(nil)
			return
		}

		window.makeFirstResponder(fileTransferTable)
		panel.makeKeyAndOrderFront(nil)
	}

	private func reloadQuickLookPanel() {
		guard QLPreviewPanel.sharedPreviewPanelExists(),
		      let panel = QLPreviewPanel.shared(),
		      panel.currentController as AnyObject? === self
		else {
			return
		}

		previewItems = selectedFileURLs
		panel.reloadData()
	}

	@objc override public nonisolated func acceptsPreviewPanelControl(_: QLPreviewPanel) -> Bool {
		true
	}

	@objc override public nonisolated func beginPreviewPanelControl(_ panel: QLPreviewPanel) {
		MainActor.assumeIsolated {
			beginPreviewPanelControlOnMainActor(panel)
		}
	}

	fileprivate func beginPreviewPanelControlOnMainActor(_ panel: QLPreviewPanel) {
		previewItems = selectedFileURLs
		panel.dataSource = self
		panel.delegate = self
	}

	@objc override public nonisolated func endPreviewPanelControl(_ panel: QLPreviewPanel) {
		MainActor.assumeIsolated {
			endPreviewPanelControlOnMainActor(panel)
		}
	}

	fileprivate func endPreviewPanelControlOnMainActor(_ panel: QLPreviewPanel) {
		panel.dataSource = nil
		panel.delegate = nil
		previewItems = []
	}

	@MainActor public func numberOfPreviewItems(in _: QLPreviewPanel!) -> Int {
		previewItems.count
	}

	@MainActor public func previewPanel(_: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! {
		guard previewItems.indices.contains(index) else {
			return nil
		}

		return previewItems[index] as NSURL
	}

	@MainActor public func previewPanel(_: QLPreviewPanel!, handle event: NSEvent!) -> Bool {
		guard [.keyDown, .keyUp].contains(event.type),
		      let characters = event.charactersIgnoringModifiers,
		      characters.utf16.count == 1,
		      let character = characters.utf16.first,
		      character == NSUpArrowFunctionKey || character == NSDownArrowFunctionKey
		else {
			return false
		}

		if event.type == .keyDown {
			fileTransferTable.keyDown(with: event)
		} else {
			fileTransferTable.keyUp(with: event)
		}

		return true
	}

	private func tableCell(forPreviewItem item: QLPreviewItem) -> FileTransferDialogTableCell? {
		guard let itemURL = item.previewItemURL else {
			return nil
		}

		for index in fileTransferTable.selectedRowIndexes {
			guard let transfer = arrangedFileTransfers[safe: index], transfer.fileURL == itemURL else {
				continue
			}

			return fileTransferTable.view(atColumn: 0, row: index, makeIfNecessary: false)
				as? FileTransferDialogTableCell
		}

		return nil
	}

	@MainActor public func previewPanel(
		_: QLPreviewPanel!,
		sourceFrameOnScreenFor item: (any QLPreviewItem)!
	) -> NSRect {
		guard let tableCell = tableCell(forPreviewItem: item) else {
			return .zero
		}

		let iconFrame = tableCell.fileIconFrameOnScreen
		let visibleRect = fileTransferTable.convert(fileTransferTable.visibleRect, to: nil)
		let visibleRectOnScreen = window.convertToScreen(visibleRect)
		return iconFrame.intersects(visibleRectOnScreen) ? iconFrame : .zero
	}

	@MainActor public func previewPanel(
		_: QLPreviewPanel!,
		transitionImageFor item: (any QLPreviewItem)!,
		contentRect _: UnsafeMutablePointer<NSRect>!
	) -> Any! {
		tableCell(forPreviewItem: item)?.fileIcon
	}

	// MARK: - Timer and table

	@objc public func updateMaintenanceTimer() {
		let activeTransfers = activeFileTransfers
		if maintenanceTimer?.timerIsActive == true {
			if activeTransfers.isEmpty {
				maintenanceTimer?.stop()
			}
		} else if activeTransfers.isEmpty == false {
			maintenanceTimer?.start(FileTransferDialogConstants.maintenanceInterval, onRepeat: true)
		}
	}

	private func onMaintenanceTimer() {
		activeFileTransfers.forEach { $0.onMaintenanceTimer() }
	}

	public func tableView(
		_ tableView: NSTableView,
		viewFor _: NSTableColumn?,
		row: Int
	) -> NSView? {
		guard let transfer = arrangedFileTransfers[safe: row],
		      let view = tableView.makeView(withIdentifier: NSUserInterfaceItemIdentifier("GroupView"), owner: self)
		      as? FileTransferDialogTableCell
		else {
			return nil
		}

		transfer.transferTableCell = view
		return view
	}

	public func tableView(_ tableView: NSTableView, didAdd _: NSTableRowView, forRow row: Int) {
		let cell = tableView.view(atColumn: 0, row: row, makeIfNecessary: false)
			as? FileTransferDialogTableCell
		cell?.prepareInitialState()
	}

	public func tableViewSelectionDidChange(_: Notification) {
		reloadQuickLookPanel()
	}

	// MARK: - Network information

	@objc public var IPAddress: String? {
		get {
			if TPCPreferences.fileTransferIPAddressDetectionMethod() == .manual {
				let address = TPCPreferences.fileTransferManuallyEnteredIPAddress()
				return address?.isEmpty == false ? address : nil
			}

			return cachedIPAddress
		}
		set { cachedIPAddress = newValue }
	}

	@MainActor @objc public func clearIPAddress() {
		IPAddress = nil
		ipAddressRequest?.cancelLookup()
		ipAddressRequest = nil
		flushIPAddressCompletionBlocks(with: nil)
	}

	@MainActor @objc(requestIPAddress:)
	public func requestIPAddress(_ completion: @escaping (String?) -> Void) {
		if let address = IPAddress {
			completion(address)
			return
		}

		let method = TPCPreferences.fileTransferIPAddressDetectionMethod()
		guard method != .manual, method != .routerOnly else {
			completion(nil)
			return
		}

		ipAddressCompletionBlocks.append(completion)
		requestIPAddress()
	}

	private func flushIPAddressCompletionBlocks(with address: String?) {
		let blocks = ipAddressCompletionBlocks
		ipAddressCompletionBlocks.removeAll()
		blocks.forEach { $0(address) }
	}

	@MainActor @objc public func requestIPAddress() {
		guard ipAddressRequest == nil else {
			return
		}

		let request = InternetAddressLookup(delegate: self)
		request.performLookup()
		ipAddressRequest = request
	}

	public nonisolated func internetAddressLookupReturnedAddress(_ address: String) {
		MainActor.assumeIsolated {
			completeIPAddressLookup(with: address)
		}
	}

	@MainActor private func completeIPAddressLookup(with address: String) {
		IPAddress = address
		for transfer in senderFileTransfers where transfer.transferStatus == .waitingForLocalIPAddress {
			transfer.noteIPAddressLookupSucceeded()
		}

		ipAddressRequest = nil
		flushIPAddressCompletionBlocks(with: address)
	}

	public nonisolated func internetAddressLookupFailed() {
		MainActor.assumeIsolated {
			completeFailedIPAddressLookup()
		}
	}

	@MainActor private func completeFailedIPAddressLookup() {
		for transfer in senderFileTransfers where transfer.transferStatus == .waitingForLocalIPAddress {
			transfer.noteIPAddressLookupFailed()
		}

		ipAddressRequest = nil
		flushIPAddressCompletionBlocks(with: nil)
	}

	// MARK: - Navigation and collection queries

	private var navigationSelection: TDCFileTransferDialogSelection {
		TDCFileTransferDialogSelection(rawValue: UInt(navigationControl.selectedSegment)) ?? .all
	}

	@IBAction private func navigationSelectionDidChange(_: Any?) {
		switch navigationSelection {
		case .sending:
			fileTransfersController.filterPredicate = NSPredicate(format: "isSender == YES")
		case .receiving:
			fileTransfersController.filterPredicate = NSPredicate(format: "isSender == NO")
		default:
			fileTransfersController.filterPredicate = nil
		}
	}

	private var arrangedFileTransfers: [TDCFileTransferDialogTransferController] {
		fileTransfersController?.arrangedObjects as? [TDCFileTransferDialogTransferController] ?? []
	}

	private var allFileTransfers: [TDCFileTransferDialogTransferController] {
		arrangedFileTransfers
	}

	private var receiverCount: Int {
		allFileTransfers.count { $0.isSender == false }
	}

	private var stoppedFileTransfers: [TDCFileTransferDialogTransferController] {
		let statuses: Set<TDCFileTransferDialogTransferStatus> = [
			.complete, .stopped, .fatalError, .recoverableError,
		]
		return fileTransfers { statuses.contains($0.transferStatus) }
	}

	private var activeFileTransfers: [TDCFileTransferDialogTransferController] {
		fileTransfers { [.receiving, .sending].contains($0.transferStatus) }
	}

	private var senderFileTransfers: [TDCFileTransferDialogTransferController] {
		fileTransfers(matching: \.isSender)
	}

	private func fileTransfers(
		matching predicate: (TDCFileTransferDialogTransferController) -> Bool
	) -> [TDCFileTransferDialogTransferController] {
		allFileTransfers.filter(predicate)
	}

	private func firstFileTransfer(
		matching predicate: (TDCFileTransferDialogTransferController) -> Bool
	) -> TDCFileTransferDialogTransferController? {
		allFileTransfers.first(where: predicate)
	}

	private var selectedFileTransfers: [TDCFileTransferDialogTransferController] {
		fileTransferTable.selectedRowIndexes.compactMap { arrangedFileTransfers[safe: $0] }
	}

	// MARK: - Window delegate and destination bookmark

	public func windowWillClose(_: Notification) {
		window.perform(NSSelectorFromString("saveWindowStateForClass:"), with: type(of: self))

		guard QLPreviewPanel.sharedPreviewPanelExists(),
		      let panel = QLPreviewPanel.shared(),
		      panel.isVisible,
		      panel.currentController as AnyObject? === self
		else {
			return
		}

		panel.orderOut(nil)
	}

	@objc public var downloadDestinationURL: URL? {
		downloadDestinationURLPrivate
	}

	@objc public func startUsingDownloadDestinationURL() {
		guard let bookmark = TPCPreferencesUserDefaults.shared().data(
			forKey: FileTransferDialogConstants.bookmarkKey
		) else {
			return
		}

		var isStale = false
		let resolvedURL: URL

		do {
			resolvedURL = try URL(
				resolvingBookmarkData: bookmark,
				options: .withSecurityScope,
				relativeTo: nil,
				bookmarkDataIsStale: &isStale
			)
		} catch {
			fileTransferDialogLogger
				.error("Error resolving download bookmark: \(error.localizedDescription, privacy: .public)")
			return
		}

		if isStale {
			guard resolvedURL.startAccessingSecurityScopedResource() else {
				fileTransferDialogLogger.error("Failed to access stale download bookmark")
				return
			}

			defer { resolvedURL.stopAccessingSecurityScopedResource() }

			do {
				let refreshed = try resolvedURL.bookmarkData(
					options: .withSecurityScope,
					includingResourceValuesForKeys: nil,
					relativeTo: nil
				)
				setDownloadDestinationURL(refreshed)
			} catch {
				fileTransferDialogLogger
					.error("Failed to refresh stale download bookmark: \(error.localizedDescription, privacy: .public)")
			}
			return
		}

		guard resolvedURL.startAccessingSecurityScopedResource() else {
			fileTransferDialogLogger.error("Failed to access download bookmark")
			return
		}

		downloadDestinationURLPrivate = resolvedURL
	}

	@objc(setDownloadDestinationURL:)
	public func setDownloadDestinationURL(_ bookmark: Data?) {
		downloadDestinationURLPrivate?.stopAccessingSecurityScopedResource()
		downloadDestinationURLPrivate = nil
		TPCPreferencesUserDefaults.shared().set(bookmark, forKey: FileTransferDialogConstants.bookmarkKey)
		startUsingDownloadDestinationURL()
	}
}

private extension Collection {
	subscript(safe index: Index) -> Element? {
		indices.contains(index) ? self[index] : nil
	}
}
