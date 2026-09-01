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
import os

public extension FileTransferDialog {
	/// Locates the transfer a DCC `RESUME`/`ACCEPT` refers to.
	///
	/// A port on its own identifies nothing: it is unique to neither a network
	/// nor a peer, so matching on it alone lets any user on any connected
	/// network move the resume offset of somebody else's transfer. The client,
	/// the peer nickname and the filename all have to agree.
	func fileTransfer(
		matchingPort port: UInt16,
		client: IRCClient,
		peerNickname: String,
		filename: String
	) -> TDCFileTransferDialogTransferController? {
		firstFileTransfer {
			$0.hostPort == port
				&& Self.transfer($0, belongsTo: client, peerNickname: peerNickname, filename: filename)
		}
	}

	internal static func transfer(
		_ transfer: TDCFileTransferDialogTransferController,
		belongsTo client: IRCClient,
		peerNickname: String,
		filename: String
	) -> Bool {
		guard transfer.clientId == client.uniqueIdentifier,
		      transfer.peerNickname.caseInsensitiveCompare(peerNickname) == .orderedSame
		else {
			return false
		}

		/* The peer echoes back the name we sent it, which crossed the wire in
		 its sanitised form, so compare the sanitised forms. */
		let ourFilename = transfer.filename.safeFilename

		return ourFilename.caseInsensitiveCompare(filename) == .orderedSame
	}

	func fileTransfer(withUniqueIdentifier identifier: String) -> TDCFileTransferDialogTransferController? {
		firstFileTransfer { $0.uniqueIdentifier == identifier }
	}

	func fileTransferExists(withToken transferToken: String) -> Bool {
		firstFileTransfer { $0.transferToken == transferToken } != nil
	}

	func fileTransferSender(
		matchingToken transferToken: String,
		client: IRCClient,
		peerNickname: String,
		filename: String
	) -> TDCFileTransferDialogTransferController? {
		firstFileTransfer {
			$0.transferToken == transferToken && $0.isSender
				&& Self.transfer($0, belongsTo: client, peerNickname: peerNickname, filename: filename)
		}
	}

	func fileTransferReceiver(matchingToken transferToken: String) -> TDCFileTransferDialogTransferController? {
		firstFileTransfer { $0.transferToken == transferToken && !$0.isSender }
	}

	func prepareForApplicationTermination() {
		downloadDestinationURLPrivate?.stopAccessingSecurityScopedResource()
		close()
		prepareForPermanentDestruction(model.transfers)
	}

	func addReceiver(
		for client: IRCClient,
		nickname: String,
		address hostAddress: String,
		port hostPort: UInt16,
		filename: String,
		filesize totalFilesize: UInt64,
		token transferToken: String?
	) -> String? {
		guard receiverCount < FileTransferDialogConstants.receiverHardLimit else {
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

		if Preferences.FileTransfers.requestReplyAction.value == .automaticallyDownload {
			controller.open(withPath: downloadDestinationURLPrivate?.path ?? PathInfo.userDownloads)
		}

		return controller.uniqueIdentifier
	}

	func addSender(
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

	internal func clientWillBeDestroyed(_ notification: Notification) {
		guard let client = notification.object as? IRCClient else { return }
		removeFileTransfers(matching: client)
	}

	internal func clearStoppedTransfers() {
		removeFileTransfers(model.stoppedTransfers)
	}

	private func startTransfers(_ transfers: [TDCFileTransferDialogTransferController]) {
		let savePath = downloadDestinationURLPrivate?.path
		var pending: [TDCFileTransferDialogTransferController] = []

		for transfer in transfers where [.stopped, .recoverableError].contains(transfer.transferStatus) {
			if transfer.isSender || transfer.path != nil {
				transfer.open()
			} else if let savePath {
				transfer.open(withPath: savePath)
			} else {
				pending.append(transfer)
			}
		}

		guard !pending.isEmpty else { return }

		let panel = NSOpenPanel()
		panel.directoryURL = PathInfo.userDownloadsURL
		panel.allowsMultipleSelection = false
		panel.canChooseDirectories = true
		panel.canChooseFiles = false
		panel.canCreateDirectories = true
		panel.resolvesAliases = true
		panel.message = FileTransferStrings.destinationPickerMessage
		panel.prompt = PromptStrings.Action.select
		panel.beginSheetModal(for: window) { response in
			guard response == .OK, let path = panel.url?.path else { return }
			pending.forEach { $0.open(withPath: path) }
		}
	}

	internal func perform(_ action: FileTransferDialogAction, on identifiers: Set<String>) {
		let transfers = model.transfers(with: identifiers)
		switch action {
		case .start:
			startTransfers(transfers)
		case .stop:
			transfers.forEach { $0.closeAndPostNotification(false) }
		case .remove:
			removeFileTransfers(transfers)
		case .open:
			openFiles(for: identifiers)
		case .reveal:
			revealFiles(for: identifiers)
		case .preview:
			model.selection = identifiers
			toggleQuickLookPanel()
		}
		model.refreshPresentation()
	}

	func updateMaintenanceTimer() {
		guard model.activeTransfers.isEmpty == false else {
			maintenanceTask?.cancel()
			maintenanceTask = nil

			return
		}

		guard maintenanceTask == nil else {
			return
		}

		maintenanceTask = Task { @MainActor [weak self] in
			while Task.isCancelled == false {
				try? await Task.sleep(for: FileTransferDialogConstants.maintenanceInterval)

				guard Task.isCancelled == false, let self else {
					return
				}

				onMaintenanceTimer()
			}
		}
	}

	internal func onMaintenanceTimer() {
		model.activeTransfers.forEach { $0.onMaintenanceTimer() }
		model.refreshPresentation()
	}

	internal var senderFileTransfers: [TDCFileTransferDialogTransferController] {
		fileTransfers(matching: \.isSender)
	}

	/// Every transfer, whatever the toolbar is showing.
	private var receiverCount: Int {
		model.receiverCount
	}

	private func addFileTransfer(_ controller: TDCFileTransferDialogTransferController) {
		/* Newest first, and stored whether or not the toolbar is showing its
		 direction — the filter is applied when the rows are built. */
		model.add(controller)
	}

	private func removeFileTransfers(matching client: IRCClient) {
		removeFileTransfers(fileTransfers { $0.client === client })
	}

	private func removeFileTransfers(_ transfers: [TDCFileTransferDialogTransferController]) {
		guard transfers.isEmpty == false else { return }

		prepareForPermanentDestruction(transfers)

		model.remove(transfers)
	}

	private func prepareForPermanentDestruction(
		_ transfers: [TDCFileTransferDialogTransferController]
	) {
		for transfer in transfers {
			transfer.prepareForPermanentDestruction()
		}
	}

	private func fileTransfers(
		matching predicate: (TDCFileTransferDialogTransferController) -> Bool
	) -> [TDCFileTransferDialogTransferController] {
		model.transfers.filter(predicate)
	}

	private func firstFileTransfer(
		matching predicate: (TDCFileTransferDialogTransferController) -> Bool
	) -> TDCFileTransferDialogTransferController? {
		model.transfers.first(where: predicate)
	}
}
