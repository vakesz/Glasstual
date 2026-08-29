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
import Synchronization

public typealias TDCFileTransferDialog = FileTransferDialog

public enum FileTransferSelection: UInt, Sendable {
	case all
	case sending
	case receiving

	/// The transfers this toolbar selection shows.
	///
	/// The array controller did this with an `isSender ==` predicate. The
	/// direction is taken as a projection rather than read off the transfer so
	/// the rule can be exercised without one.
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

nonisolated enum FileTransferSection: Hashable, Sendable { // nonisolated: value
	case transfers
}

/// Rows are identified by the transfer's `uniqueIdentifier`.
typealias FileTransferDataSource =
	NSTableViewDiffableDataSource<FileTransferSection, String>

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

/// What the window's Quick Look overrides are allowed to answer.
///
/// QuickLookUI declares `QLPreviewPanelController` on `NSObject` without
/// isolation, so the overrides below cannot be main-actor. Rather than reach
/// across isolation for the answer, they read this snapshot, which the dialog
/// writes on the main actor.
nonisolated struct FileTransferPreviewState: Sendable { // nonisolated: value
	var acceptsPreviews = false
}

@objc(TDCFileTransferDialogWindow)
public final class FileTransferDialogWindow: NSWindow {
	nonisolated let previewState = Mutex(FileTransferPreviewState()) // nonisolated: let

	override public nonisolated func acceptsPreviewPanelControl(_: QLPreviewPanel!) -> Bool { // nonisolated: pure
		previewState.withLock { $0.acceptsPreviews }
	}

	/** The dialog points the shared panel at itself before the panel appears,
	 in `toggleQuickLookPanel()`, so these two only have to confirm it and can
	 wait for a main-actor turn. Nothing crosses isolation: the panel is a
	 singleton the main actor fetches for itself. */
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

	/// Every transfer the dialog knows about, newest first.
	///
	/// The array controller used to hold these, and `arrangedObjects` handed
	/// back only the ones its filter predicate let through — which is why the
	/// receiver limit, the Clear button and the maintenance timer all used to
	/// stop seeing transfers the toolbar had filtered out. The whole set lives
	/// here and `arrangedFileTransfers` is the part the table draws.
	var storedFileTransfers: [TDCFileTransferDialogTransferController] = []
	var transferDataSource: FileTransferDataSource?

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

		let transferDataSource = makeTransferDataSource()
		self.transferDataSource = transferDataSource
		fileTransferTable.dataSource = transferDataSource

		prepareTableMenu()
		installKeyDownEventMonitor()
		setPreviewsAccepted(true)

		notifications.observe(.ircWorldWillDestroyClient) { [weak self] notification in
			self?.clientWillBeDestroyed(notification)
		}
	}

	/// Tells the window's nonisolated Quick Look overrides whether this dialog
	/// is still there to answer for them.
	private func setPreviewsAccepted(_ accepted: Bool) {
		(window as? FileTransferDialogWindow)?.previewState.withLock {
			$0.acceptsPreviews = accepted
		}
	}

	isolated deinit {
		setPreviewsAccepted(false)
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
