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

import CocoaExtensions
import Foundation
import os

public extension FileTransferCenter {
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
		filename: String,
		isSender: Bool? = nil
	) -> FileTransferController? {
		firstFileTransfer {
			$0.hostPort == port
				&& !$0.isReversed && (isSender == nil || $0.isSender == isSender)
				&& Self.transfer($0, belongsTo: client, peerNickname: peerNickname, filename: filename)
		}
	}

	internal static func transfer(
		_ transfer: FileTransferController,
		belongsTo client: IRCClient,
		peerNickname: String,
		filename: String
	) -> Bool {
		let ourPeer = client.supportInfo.casefoldString(transfer.peerNickname)
		let theirPeer = client.supportInfo.casefoldString(peerNickname)

		guard transfer.clientId == client.uniqueIdentifier, ourPeer == theirPeer else {
			return false
		}

		/* The peer echoes back the name we sent it, which crossed the wire in
		 its sanitised form, so compare the sanitised forms. */
		let ourFilename = transfer.wireFilename

		return ourFilename == filename
	}

	func fileTransfer(withUniqueIdentifier identifier: String) -> FileTransferController? {
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
	) -> FileTransferController? {
		firstFileTransfer {
			$0.transferToken == transferToken && $0.isSender
				&& Self.transfer($0, belongsTo: client, peerNickname: peerNickname, filename: filename)
		}
	}

	func fileTransfer(
		matchingToken token: String,
		client: IRCClient,
		peerNickname: String,
		filename: String,
		isSender: Bool
	) -> FileTransferController? {
		firstFileTransfer {
			$0.isReversed && $0.transferToken == token && $0.isSender == isSender
				&& Self.transfer($0, belongsTo: client, peerNickname: peerNickname, filename: filename)
		}
	}

	/// What the downloads already running or waiting still have to write. The
	/// next offer has to fit alongside them, not after them.
	var pendingReceiveByteCount: UInt64 {
		model.pendingReceiveByteCount
	}

	/** Whether the volume `path` is on can still take `byteCount` bytes.

	 `volumeAvailableCapacityForImportantUsage` is the figure that accounts for
	 what the system would purge to make room, which is what a download the user
	 asked for gets to use. A volume that will not answer at all — a network
	 mount, a path that does not exist yet — is not evidence of being full, so
	 the transfer is allowed to try and to fail the ordinary way. */
	static func destination(_ path: String?, hasRoomFor byteCount: UInt64) -> Bool {
		guard byteCount > 0, let path, path.isEmpty == false else {
			return true
		}

		let values = try? URL(fileURLWithPath: path).resourceValues(
			forKeys: [.volumeAvailableCapacityForImportantUsageKey]
		)

		guard let available = values?.volumeAvailableCapacityForImportantUsage else {
			return true
		}

		return available >= 0 && UInt64(available) >= byteCount
	}

	func prepareForApplicationTermination() {
		workspace.cancelPendingWork()
		prepareForPermanentDestruction(model.transfers)
		clearIPAddress()
		downloadDestinationURLPrivate?.stopAccessingSecurityScopedResource()
		downloadDestinationURLPrivate = nil
		SharedApplication.sharedApplicationScenes().closeFileTransfers()
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
		guard receiverCount < FileTransferConstants.receiverHardLimit else {
			fileTransferLogger.error(
				"Maximum receiver count of \(FileTransferConstants.receiverHardLimit, privacy: .public) exceeded"
			)
			/* Dropping the offer silently reads as the sender never sending it.
			 The user is the only one who can do anything about it — clear the
			 finished rows — so the user is the one who has to be told. */
			client.printDebugInformation(
				toConsole: ConnectionSafetyStrings.FileTransfer.refusedBecauseCrowded(sender: nickname)
			)
			return nil
		}

		guard let controller = FileTransferController.receiver(
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

		present()
		addFileTransfer(controller)

		if Preferences.FileTransfers.requestReplyAction.value == .automaticallyDownload {
			let destinationPath = downloadDestinationURLPrivate?.path ?? PathInfo.userDownloads

			/* Reserving the file first and finding out on the last block that the
			 volume was full leaves a part-written download and a peer that spent
			 the whole transfer on it. The offer states its size up front, so the
			 room for it — beside what the downloads already running still have to
			 write — can be settled before anything is accepted. */
			guard Self.destination(destinationPath, hasRoomFor: totalFilesize + pendingReceiveByteCount) else {
				fileTransferLogger.error("Refused an automatic download the destination volume has no room for")
				controller.close(with: .storageFull, isFatalError: true)

				return controller.uniqueIdentifier
			}

			controller.destinationAccessURL = downloadDestinationURLPrivate
			controller.open(withPath: destinationPath)
		}

		return controller.uniqueIdentifier
	}

	func addSender(
		for client: IRCClient,
		nickname: String,
		path: String,
		autoOpen: Bool,
		accessURL: URL? = nil
	) -> String? {
		guard let controller = FileTransferController.sender(
			for: client,
			nickname: nickname,
			path: path,
			accessURL: accessURL
		) else {
			return nil
		}

		present()
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

	private func startTransfers(_ transfers: [FileTransferController]) {
		let savePath = downloadDestinationURLPrivate?.path
		var pending: [FileTransferController] = []

		for transfer in transfers where transfer.canStart {
			if transfer.isSender || transfer.path != nil {
				transfer.open()
			} else if let savePath {
				transfer.destinationAccessURL = downloadDestinationURLPrivate
				transfer.open(withPath: savePath)
			} else {
				pending.append(transfer)
			}
		}

		guard !pending.isEmpty else { return }

		pendingDestinationTransferIDs.formUnion(pending.map(\.uniqueIdentifier))
		model.isChoosingDestination = true
	}

	func completeDestinationSelection(_ result: Result<URL, Error>) {
		defer { pendingDestinationTransferIDs = [] }
		guard case let .success(url) = result else { return }
		for transfer in model.transfers(with: pendingDestinationTransferIDs) {
			guard !transfer.isSender, transfer.canStart else { continue }
			transfer.destinationAccessURL = url
			transfer.open(withPath: url.path)
		}
	}

	internal func perform(_ action: FileTransferAction, on identifiers: Set<String>) {
		let transfers = model.transfers(with: identifiers)
		switch action {
		case .start:
			startTransfers(transfers)
		case .stop:
			transfers.forEach { $0.closeAndPostNotification(false) }
		case .remove:
			removeFileTransfers(transfers)
		case .open:
			workspace.open(model.selectedLocalFiles(for: identifiers))
		case .reveal:
			workspace.reveal(model.selectedLocalFiles(for: identifiers))
		case .preview:
			model.selection = identifiers
			model.presentPreview()
		}
		model.refreshPresentation()
	}

	/// Notification actions use the same start/destination workflow as the list.
	internal func respondToNotification(for identifier: String, clientIdentifier: String?, accept: Bool) -> Bool {
		guard let transfer = fileTransfer(withUniqueIdentifier: identifier),
		      clientIdentifier == nil || clientIdentifier == transfer.clientId else { return false }
		model.filter = .all
		model.selection = [identifier]
		if accept, !transfer.isSender, transfer.transferStatus == .stopped {
			perform(.start, on: [identifier])
		}
		return true
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
				try? await Task.sleep(for: FileTransferConstants.maintenanceInterval)

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

	internal var senderFileTransfers: [FileTransferController] {
		fileTransfers(matching: \.isSender)
	}

	/// Every transfer, whatever the toolbar is showing.
	private var receiverCount: Int {
		model.receiverCount
	}

	private func addFileTransfer(_ controller: FileTransferController) {
		/* Newest first, and stored whether or not the toolbar is showing its
		 direction — the filter is applied when the rows are built. */
		model.add(controller)
	}

	private func removeFileTransfers(matching client: IRCClient) {
		removeFileTransfers(fileTransfers { $0.client === client })
	}

	private func removeFileTransfers(_ transfers: [FileTransferController]) {
		guard transfers.isEmpty == false else { return }

		prepareForPermanentDestruction(transfers)

		model.remove(transfers)
	}

	private func prepareForPermanentDestruction(
		_ transfers: [FileTransferController]
	) {
		for transfer in transfers {
			transfer.prepareForPermanentDestruction()
		}
	}

	private func fileTransfers(
		matching predicate: (FileTransferController) -> Bool
	) -> [FileTransferController] {
		model.transfers.filter(predicate)
	}

	private func firstFileTransfer(
		matching predicate: (FileTransferController) -> Bool
	) -> FileTransferController? {
		model.transfers.first(where: predicate)
	}
}
