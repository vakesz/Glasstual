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

extension FileTransferCenter {
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
		isSender: Bool
	) -> FileTransferController? {
		model.transfers.first {
			$0.hostPort == port && !$0.isReversed && $0.isSender == isSender
				&& Self.transfer($0, belongsTo: client, peerNickname: peerNickname, filename: filename)
		}
	}

	static func transfer(
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
		return transfer.wireFilename == filename
	}

	func fileTransfer(withUniqueIdentifier identifier: String) -> FileTransferController? {
		model.transfers.first { $0.uniqueIdentifier == identifier }
	}

	func fileTransferExists(withToken transferToken: String) -> Bool {
		model.transfers.contains { $0.transferToken == transferToken }
	}

	func fileTransferSender(
		matchingToken transferToken: String,
		client: IRCClient,
		peerNickname: String,
		filename: String
	) -> FileTransferController? {
		model.transfers.first {
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
		model.transfers.first {
			$0.isReversed && $0.transferToken == token && $0.isSender == isSender
				&& Self.transfer($0, belongsTo: client, peerNickname: peerNickname, filename: filename)
		}
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
		senderPreparations.values.forEach { $0.cancel() }
		senderPreparations.removeAll()
		workspace.cancelPendingWork()
		for transfer in model.transfers {
			transfer.prepareForPermanentDestruction()
		}
		clearIPAddress()
		downloadDestinationURLPrivate?.stopAccessingSecurityScopedResource()
		downloadDestinationURLPrivate = nil
		dismiss()
	}

	/** Whether an offer downloads without the user accepting it.

	 Only when the user asked for that, only from a peer they already know — the
	 whole network can send an offer — and only up to a size that cannot fill a
	 disk on a stranger's say-so. Anything else waits in the list for Accept. */
	static func downloadsAutomatically(
		_ behavior: FileTransferRequestBehavior,
		peerIsKnown: Bool,
		filesize: UInt64
	) -> Bool {
		behavior == .automaticallyDownload && peerIsKnown && filesize <= FileTransferConstants.automaticDownloadSizeLimit
	}

	func addReceiver(
		for client: IRCClient,
		nickname: String,
		address hostAddress: String,
		port hostPort: UInt16,
		filename: String,
		filesize totalFilesize: UInt64,
		token transferToken: String?,
		peerIsKnown: Bool
	) -> String? {
		guard model.receiverCount < FileTransferConstants.receiverHardLimit else {
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

		/* Not brought forward: the offer arrived unasked, and the window taking
		 focus for each one is what made a flood of them unusable. The row, the
		 notification and the transcript line are how the user hears of it. */
		model.add(controller)

		if Self.downloadsAutomatically(
			Preferences.FileTransfers.requestReplyAction.value,
			peerIsKnown: peerIsKnown,
			filesize: totalFilesize
		) {
			let destinationPath = downloadDestinationURLPrivate?.path ?? PathInfo.userDownloads

			/* Reserving the file first and finding out on the last block that the
			 volume was full leaves a part-written download and a peer that spent
			 the whole transfer on it. The offer states its size up front, so the
			 room for it — beside what the downloads already running still have to
			 write — can be settled before anything is accepted. */
			let required = totalFilesize + model.pendingReceiveByteCount
			guard Self.destination(destinationPath, hasRoomFor: required) else {
				fileTransferLogger.error("Refused an automatic download the destination volume has no room for")
				controller.close(with: .storageFull, isFatalError: true)

				return controller.uniqueIdentifier
			}

			controller.destinationAccessURL = downloadDestinationURLPrivate
			controller.open(withPath: destinationPath)
		}

		return controller.uniqueIdentifier
	}

	/// Owns file preparation started by a synchronous menu or IRC command.
	func offerSender(
		for client: IRCClient, nickname: String, path: String, autoOpen: Bool,
		accessURL: URL? = nil, completion: @escaping (String?) -> Void = { _ in }
	) {
		let identifier = UUID()
		senderPreparations[identifier] = Task { [weak self] in
			guard let self else { return }
			let result = await addSender(for: client, nickname: nickname, path: path,
			                             autoOpen: autoOpen, accessURL: accessURL)
			senderPreparations[identifier] = nil
			guard !Task.isCancelled else { return }
			completion(result)
		}
	}

	func addSender(
		for client: IRCClient,
		nickname: String,
		path: String,
		autoOpen: Bool,
		accessURL: URL? = nil
	) async -> String? {
		let session = client.startup.identifier
		guard let controller = await FileTransferController.sender(
			for: client,
			nickname: nickname,
			path: path,
			accessURL: accessURL
		) else {
			return nil
		}

		guard !Task.isCancelled, !client.isTerminating, client.startup.identifier == session else {
			controller.prepareForPermanentDestruction()
			await controller.stopTask?.value
			return nil
		}
		present()
		model.add(controller)

		if autoOpen {
			controller.open()
		}

		return controller.uniqueIdentifier
	}

	func clientWillBeDestroyed(_ notification: Notification) {
		guard let client = notification.object as? IRCClient else { return }
		removeFileTransfers(model.transfers.filter { $0.client === client })
	}

	func clearStoppedTransfers() {
		removeFileTransfers(model.stoppedTransfers)
	}

	func perform(_ action: FileTransferAction, on identifiers: Set<String>) {
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
	}

	/** Brings the transfer a notification names into view, and starts it when
	 the notification's Accept action asked for that.

	 Opening the notification is a request to see the transfer, so the filter is
	 widened to make sure the row it names is actually on screen. */
	func respondToNotification(for identifier: String, clientIdentifier: String?, accept: Bool) -> Bool {
		guard let transfer = notifiedTransfer(identifier, of: clientIdentifier) else { return false }
		model.filter = .all
		model.selection = [identifier]
		if accept, !transfer.isSender, transfer.transferStatus == .stopped {
			perform(.start, on: [identifier])
		}
		return true
	}

	/** Refuses the transfer a notification's Decline action names.

	 Answered where it was asked: the person has said what they wanted, and a
	 window they did not open has no business changing its filter and selection
	 on the strength of it.

	 An offer nobody accepted is removed outright. Stopping it did nothing — it
	 was already stopped — so Decline left the offer sitting in the list exactly
	 as it was. A transfer already under way is stopped instead, and stays listed
	 with whatever it got through. */
	@discardableResult
	func declineNotification(for identifier: String, clientIdentifier: String?) -> Bool {
		guard let transfer = notifiedTransfer(identifier, of: clientIdentifier) else { return false }
		if transfer.isSender == false, transfer.transferStatus == .stopped {
			removeFileTransfers([transfer])
		} else {
			transfer.closeAndPostNotification(false)
		}
		return true
	}

	/// The transfer a notification names, if it is still listed and still
	/// belongs to the connection the notification was posted for.
	private func notifiedTransfer(_ identifier: String, of clientIdentifier: String?) -> FileTransferController? {
		guard let transfer = fileTransfer(withUniqueIdentifier: identifier),
		      clientIdentifier == nil || clientIdentifier == transfer.clientId
		else {
			return nil
		}

		return transfer
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

	func onMaintenanceTimer() {
		model.activeTransfers.forEach { $0.onMaintenanceTimer() }
	}

	private func startTransfers(_ transfers: [FileTransferController]) {
		let savePath = downloadDestinationURLPrivate?.path
		var pending: [FileTransferController] = []

		for transfer in transfers where transfer.canStart {
			if transfer.isSender {
				transfer.open()
			} else if let path = transfer.path {
				guard claimRoom(for: transfer, at: path) else { continue }
				transfer.open()
			} else if let savePath {
				guard claimRoom(for: transfer, at: savePath) else { continue }
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

	/** Answers the folder picker the pending downloads were waiting on.

	 A picker the user cancelled leaves the transfers where they were, ready to
	 be started again. One that failed has no folder to offer them, and saying
	 nothing left the rows looking as though Start had never been pressed. */
	func completeDestinationSelection(_ result: Result<URL, Error>) {
		let pending = model.transfers(with: pendingDestinationTransferIDs)
		pendingDestinationTransferIDs = []

		let url: URL
		switch result {
		case let .success(chosen):
			url = chosen
		case let .failure(error):
			fileTransferLogger.error(
				"Could not choose a download folder: \(error.localizedDescription, privacy: .public)"
			)
			for transfer in pending where transfer.canStart {
				transfer.close(with: .fileHandlerFailed)
			}
			return
		}

		for transfer in pending {
			guard !transfer.isSender, transfer.canStart, claimRoom(for: transfer, at: url.path) else { continue }
			transfer.destinationAccessURL = url
			transfer.open(withPath: url.path)
		}
	}

	/** Whether the download can start at `path` without running out of room,
	 failing it in a way Try Again can get past when not.

	 The automatic download always asked this; a download the user accepted by
	 hand did not, and found out on the last block. The downloads already
	 running still have their own bytes to write, so the room has to be there
	 beside theirs. */
	private func claimRoom(for transfer: FileTransferController, at path: String) -> Bool {
		let remaining = transfer.totalFilesize > transfer.processedFilesize
			? transfer.totalFilesize - transfer.processedFilesize
			: 0
		let (required, overflow) = remaining.addingReportingOverflow(model.pendingReceiveByteCount)
		guard Self.destination(path, hasRoomFor: overflow ? .max : required) else {
			fileTransferLogger.error("Refused to start a download the destination volume has no room for")
			transfer.close(with: .storageFull)
			return false
		}
		return true
	}

	private func removeFileTransfers(_ transfers: [FileTransferController]) {
		guard transfers.isEmpty == false else { return }

		for transfer in transfers {
			transfer.prepareForPermanentDestruction()
		}

		model.remove(transfers)
	}
}
