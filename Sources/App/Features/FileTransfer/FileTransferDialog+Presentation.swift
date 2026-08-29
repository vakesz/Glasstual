/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
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
import CocoaExtensions
import QuickLookUI

extension FileTransferDialog {
	func prepareTableMenu() {
		guard let menu = fileTransferTable.menu else { return }

		menu.delegate = self
		menu.item(withTag: FileTransferDialogConstants.quickLookMenuTag)?.image = menuItemImage(
			forSymbolNamed: "eye"
		)
		menu.item(withTag: FileTransferDialogConstants.revealMenuTag)?.image = menuItemImage(
			forSymbolNamed: "folder"
		)
	}

	func installKeyDownEventMonitor() {
		keyDownEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
			guard let self, keyDownEventTogglesQuickLook(event) else { return event }

			toggleQuickLookPanel()
			return nil
		}
	}

	func removeKeyDownEventMonitor() {
		guard let keyDownEventMonitor else { return }

		NSEvent.removeMonitor(keyDownEventMonitor)
		self.keyDownEventMonitor = nil
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
			window.ce_restoreState(for: Self.self)
		}
	}

	public func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
		let transfers = selectedFileTransfers
		guard !transfers.isEmpty else { return false }

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

	public func menuNeedsUpdate(_ menu: NSMenu) {
		guard let tableMenu = fileTransferTable.menu, menu === tableMenu else { return }

		let index = menu.indexOfItem(withTag: FileTransferDialogConstants.shareMenuTag)
		guard index >= 0 else { return }

		menu.removeItem(at: index)
		var items = selectedFileURLs
		if items.count != fileTransferTable.selectedRowIndexes.count {
			items = []
		}

		guard let shareItem = AppController.shared.menuController?.shareMenuItem(forItems: items) else {
			return
		}
		shareItem.tag = FileTransferDialogConstants.shareMenuTag
		menu.insertItem(shareItem, at: index)
	}

	func beginPreviewPanelControlOnMainActor(_ panel: QLPreviewPanel) {
		previewItems = selectedFileURLs
		panel.dataSource = self
		panel.delegate = self
	}

	func endPreviewPanelControlOnMainActor(_ panel: QLPreviewPanel) {
		/* Control comes back on a later main-actor turn than the one that gave
		 it up, so a quick reopen can get there first. Only tear down if the
		 panel really has gone. */
		guard !panel.isVisible else { return }

		panel.dataSource = nil
		panel.delegate = nil
		previewItems = []
	}

	@MainActor public func numberOfPreviewItems(in _: QLPreviewPanel!) -> Int {
		previewItems.count
	}

	@MainActor public func previewPanel(_: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! {
		guard previewItems.indices.contains(index) else { return nil }
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

	@MainActor public func previewPanel(
		_: QLPreviewPanel!,
		sourceFrameOnScreenFor item: (any QLPreviewItem)!
	) -> NSRect {
		guard let tableCell = tableCell(forPreviewItem: item) else { return .zero }

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

	public func windowWillClose(_: Notification) {
		window.ce_saveState(for: Self.self)

		guard QLPreviewPanel.sharedPreviewPanelExists(),
		      let panel = QLPreviewPanel.shared(),
		      panel.isVisible,
		      controlsPreviewPanel(panel)
		else {
			return
		}

		panel.orderOut(nil)
	}

	/** Whether the shared Quick Look panel is showing this dialog's items.

	 The panel's controller is the *window*: `beginPreviewPanelControl` travels
	 the responder chain, and the dialog is the window's delegate rather than a
	 responder. The comparison used to be against the dialog, so it never
	 matched: the panel was not ordered out when the dialog closed and did not
	 reload when the selection changed. */
	func controlsPreviewPanel(_ panel: QLPreviewPanel) -> Bool {
		Self.previewPanel(controlledBy: panel.currentController, is: window)
	}

	static func previewPanel(controlledBy controller: Any?, is window: NSWindow?) -> Bool {
		guard let window else {
			return false
		}

		return controller as AnyObject? === window
	}

	@IBAction private func openReceivedFile(_: Any?) {
		selectedFileURLs.forEach { NSWorkspace.shared.open($0) }
	}

	@IBAction private func revealReceivedFileInFinder(_: Any?) {
		guard !selectedFileURLs.isEmpty else { return }
		NSWorkspace.shared.activateFileViewerSelecting(selectedFileURLs)
	}

	@IBAction private func quickLookFile(_: Any?) {
		toggleQuickLookPanel()
	}

	@IBAction private func hideWindow(_: Any?) {
		close()
	}

	private var activeOrPendingStatuses: Set<FileTransferStatus> {
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

	private var selectedFileTransfersWithLocalFiles: [TDCFileTransferDialogTransferController] {
		selectedFileTransfers.filter(fileTransferHasLocalFile)
	}

	private var selectedFileURLs: [URL] {
		selectedFileTransfersWithLocalFiles.compactMap(\.fileURL)
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

	private func keyDownEventTogglesQuickLook(_ event: NSEvent) -> Bool {
		guard event.window === window,
		      window.firstResponder === fileTransferTable as NSResponder,
		      event.modifierFlags.isDisjoint(with: .deviceIndependentFlagsMask),
		      event.charactersIgnoringModifiers == " "
		else {
			return false
		}

		return !selectedFileTransfersWithLocalFiles.isEmpty
	}

	private func fileTransferHasLocalFile(_ fileTransfer: TDCFileTransferDialogTransferController) -> Bool {
		if !fileTransfer.isSender, fileTransfer.transferStatus != .complete {
			return false
		}

		guard let filePath = fileTransfer.filePath else { return false }
		return FileManager.default.fileExists(atPath: filePath)
	}

	private func toggleQuickLookPanel() {
		guard let panel = QLPreviewPanel.shared() else { return }

		if QLPreviewPanel.sharedPreviewPanelExists(), panel.isVisible, controlsPreviewPanel(panel) {
			panel.orderOut(nil)
			return
		}

		/* Point the panel at this dialog before it appears: the responder-chain
		 callback that would otherwise do it cannot answer synchronously. */
		beginPreviewPanelControlOnMainActor(panel)

		window.makeFirstResponder(fileTransferTable)
		panel.makeKeyAndOrderFront(nil)
	}

	private func tableCell(forPreviewItem item: QLPreviewItem) -> FileTransferDialogTableCell? {
		guard let itemURL = item.previewItemURL else { return nil }

		for index in fileTransferTable.selectedRowIndexes {
			guard let transfer = fileTransfer(atArrangedIndex: index), transfer.fileURL == itemURL else {
				continue
			}

			return fileTransferTable.view(atColumn: 0, row: index, makeIfNecessary: false)
				as? FileTransferDialogTableCell
		}

		return nil
	}

	func reloadQuickLookPanel() {
		guard QLPreviewPanel.sharedPreviewPanelExists(),
		      let panel = QLPreviewPanel.shared(),
		      controlsPreviewPanel(panel)
		else {
			return
		}

		previewItems = selectedFileURLs
		panel.reloadData()
	}
}
