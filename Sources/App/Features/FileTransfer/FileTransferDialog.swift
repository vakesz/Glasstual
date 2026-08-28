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
import os
import QuickLookUI

public typealias TDCFileTransferDialog = FileTransferDialog

@objc(TDCFileTransferDialogSelection)
public enum FileTransferSelection: UInt, Sendable {
	case all
	case sending
	case receiving
}

enum FileTransferDialogConstants {
	static let receiverHardLimit = 120
	static let quickLookMenuTag = 3007
	static let shareMenuTag = 3008
	static let revealMenuTag = 3006
	static let bookmarkKey = "File Transfers -> File Transfer Download Folder Bookmark"
	static let maintenanceInterval: Duration = .seconds(1)
}

let fileTransferDialogLogger = Logger(
	subsystem: Bundle.main.bundleIdentifier ?? "Glasstual",
	category: "FileTransferDialog"
)

@objc(TDCFileTransferDialogWindow)
public final class FileTransferDialogWindow: NSWindow {
	/* ISOLATION-EXCEPTION: QuickLookUI declares the `QLPreviewPanelController`
	 methods on `NSObject` as nonisolated, so these overrides cannot be isolated.
	 QuickLook drives the panel from the main thread. */
	override public nonisolated func acceptsPreviewPanelControl(_: QLPreviewPanel!) -> Bool {
		MainActor.assumeIsolated {
			delegate is FileTransferDialog
		}
	}

	/* ISOLATION-EXCEPTION: see `acceptsPreviewPanelControl(_:)` above. */
	override public nonisolated func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
		guard let panel else { return }

		MainActor.assumeIsolated {
			(delegate as? FileTransferDialog)?.beginPreviewPanelControlOnMainActor(panel)
		}
	}

	/* ISOLATION-EXCEPTION: see `acceptsPreviewPanelControl(_:)` above. */
	override public nonisolated func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
		guard let panel else { return }

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
	InternetAddressLookupDelegate
{
	@IBOutlet var clearButton: NSButton!
	@IBOutlet var navigationControl: NSSegmentedControl!
	@IBOutlet public var fileTransferTable: BasicTableView!
	@IBOutlet var fileTransfersController: NSArrayController!

	var ipAddressRequest: InternetAddressLookup?
	var maintenanceTask: Task<Void, Never>?
	var downloadDestinationURLPrivate: URL?
	var keyDownEventMonitor: Any?
	var previewItems: [URL] = []
	var ipAddressCompletionBlocks: [(String?) -> Void] = []
	var cachedIPAddress: String?
	private lazy var notifications = NotificationSubscriptions()

	override public init() {
		super.init()
		prepareInitialState()
	}

	private func prepareInitialState() {
		Bundle.main.loadNibNamed("TDCFileTransferDialog", owner: self, topLevelObjects: nil)
		fileTransferTable.style = .inset
		prepareTableMenu()
		installKeyDownEventMonitor()

		notifications.observe(.ircWorldWillDestroyClient) { [weak self] notification in
			self?.clientWillBeDestroyed(notification)
		}
	}

	isolated deinit {
		notifications.cancelAll()
		maintenanceTask?.cancel()
		removeKeyDownEventMonitor()
	}

	override public func show() {
		show(true, restorePosition: true)
	}

	/* Quick Look walks the responder chain from the first responder, so the
	 window's overrides above answer first and forward here; a second set of
	 overrides on the dialog was never reached. */
}
