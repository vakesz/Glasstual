/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
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
import SwiftUI
import Synchronization

public typealias TDCFileTransferDialog = FileTransferDialog

public enum FileTransferSelection: UInt, CaseIterable, Identifiable, Sendable {
	case all
	case sending
	case receiving

	public var id: UInt {
		rawValue
	}

	public func shownTransfers<Transfer>(
		in transfers: [Transfer],
		isSender: (Transfer) -> Bool
	) -> [Transfer] {
		switch self {
		case .all:
			transfers
		case .sending:
			transfers.filter(isSender)
		case .receiving:
			transfers.filter { isSender($0) == false }
		}
	}
}

enum FileTransferDialogConstants {
	static let receiverHardLimit = 120
	static let bookmarkKey = "File Transfers -> File Transfer Download Folder Bookmark"
	static let maintenanceInterval: Duration = .seconds(1)
}

let fileTransferDialogLogger = Logger(
	subsystem: Bundle.main.bundleIdentifier ?? "Glasstual",
	category: "FileTransferDialog"
)

nonisolated struct FileTransferPreviewState: Sendable { // nonisolated: value
	var acceptsPreviews = false
}

public final class FileTransferDialogWindow: NSWindow {
	nonisolated let previewState = Mutex(FileTransferPreviewState()) // nonisolated: let

	override public nonisolated func acceptsPreviewPanelControl(_: QLPreviewPanel!) -> Bool { // nonisolated: pure
		previewState.withLock { $0.acceptsPreviews }
	}

	override public nonisolated func beginPreviewPanelControl(_: QLPreviewPanel!) { // nonisolated: pure
		Task { @MainActor in
			guard let panel = QLPreviewPanel.shared() else { return }
			(delegate as? FileTransferDialog)?.beginPreviewPanelControlOnMainActor(panel)
		}
	}

	override public nonisolated func endPreviewPanelControl(_: QLPreviewPanel!) { // nonisolated: pure
		Task { @MainActor in
			guard let panel = QLPreviewPanel.shared() else { return }
			(delegate as? FileTransferDialog)?.endPreviewPanelControlOnMainActor(panel)
		}
	}
}

@MainActor
public final class FileTransferDialog: WindowBase,
	NSWindowDelegate,
	QLPreviewPanelDataSource,
	QLPreviewPanelDelegate,
	InternetAddressLookupDelegate
{
	let model = FileTransferDialogModel()

	var ipAddressRequest: InternetAddressLookup?
	var maintenanceTask: Task<Void, Never>?
	var downloadDestinationURLPrivate: URL?
	var previewItems: [URL] = []
	var ipAddressCompletionBlocks: [(String?) -> Void] = []
	var cachedIPAddress: String?
	private lazy var notifications = NotificationSubscriptions()

	override public init() {
		super.init()
		installWindow()
		setPreviewsAccepted(true)

		notifications.observe(.ircWorldWillDestroyClient) { [weak self] notification in
			self?.clientWillBeDestroyed(notification)
		}
	}

	private func installWindow() {
		let rootView = FileTransferDialogView(
			model: model,
			perform: { [weak self] action, identifiers in self?.perform(action, on: identifiers) },
			clearStopped: { [weak self] in self?.clearStoppedTransfers() },
			selectionChanged: { [weak self] in self?.reloadQuickLookPanel() },
			close: { [weak self] in self?.close() }
		)
		let transferWindow = FileTransferDialogWindow(
			contentRect: NSRect(x: 0, y: 0, width: 680, height: 440),
			styleMask: [.titled, .closable, .miniaturizable, .resizable],
			backing: .buffered,
			defer: false
		)

		transferWindow.contentViewController = NSHostingController(rootView: rootView)
		transferWindow.contentMinSize = NSSize(width: 620, height: 360)
		transferWindow.contentMaxSize = NSSize(width: 1000, height: 900)
		transferWindow.delegate = self
		transferWindow.isReleasedWhenClosed = false
		transferWindow.isRestorable = false
		transferWindow.tabbingMode = .disallowed
		transferWindow.preventsApplicationTerminationWhenModal = false
		transferWindow.autorecalculatesKeyViewLoop = true
		transferWindow.title = FileTransferStrings.fileTransfers
		window = transferWindow
	}

	private func setPreviewsAccepted(_ accepted: Bool) {
		(window as? FileTransferDialogWindow)?.previewState.withLock {
			$0.acceptsPreviews = accepted
		}
	}

	isolated deinit {
		setPreviewsAccepted(false)
		notifications.cancelAll()
		maintenanceTask?.cancel()
	}

	override public func show() {
		show(true, restorePosition: true)
	}
}
