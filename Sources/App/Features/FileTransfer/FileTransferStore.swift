// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
import CocoaExtensions
import Foundation
import os

enum FileTransferConstants {
	static let receiverHardLimit = 120
	/// The largest offer that downloads without being accepted, even from a
	/// known peer. Anything larger waits for the user.
	static let automaticDownloadSizeLimit: UInt64 = 512 * 1024 * 1024
	static let maintenanceInterval: TimeInterval = 1
}

@MainActor
final class FileTransferStore {
	let model = FileTransferList()

	/// Ticks while a transfer is running, so every row's speed, progress and
	/// stall deadline are read on one cadence.
	private lazy var maintenanceTimer = SessionTimer { [weak self] _ in
		self?.onMaintenanceTimer()
	}

	var senderPreparations: [UUID: Task<Void, Never>] = [:]
	var customDownloadDestinationURL: URL?
	let defaultDownloadDestinationURL: URL?
	/// The lookup every transfer waiting on an address shares, so two concurrent
	/// DCC offers ask the address service once between them.
	var ipAddressLookup: Task<String?, Never>?
	var cachedIPAddress: String?
	/// Where an address lookup asks. The public service, except in tests.
	let addressSource: @MainActor () async -> String?
	private var networkChanges: Task<Void, Never>?
	var pendingDestinationTransferIDs: Set<String> = []
	let workspace = FileTransferWorkspace()
	private lazy var notifications = NotificationSubscriptions()

	init(
		addressSource: @escaping @MainActor () async -> String? = { await InternetAddressLookup.address() },
		defaultDownloadDestinationURL: URL? = ApplicationPaths.userDownloadsURL
	) {
		self.addressSource = addressSource
		self.defaultDownloadDestinationURL = defaultDownloadDestinationURL
		notifications.observe(.chatSessionWillDestroySession) { [weak self] notification in
			self?.sessionWillBeDestroyed(notification)
		}
		networkChanges = followNetworkChanges()
	}

	func present() {
		AppServices.scenes.open(ApplicationSceneID.fileTransfers)
	}

	func dismiss() {
		AppServices.scenes.dismiss(ApplicationSceneID.fileTransfers)
	}

	isolated deinit {
		notifications.cancelAll()
		senderPreparations.values.forEach { $0.cancel() }
		networkChanges?.cancel()
		ipAddressLookup?.cancel()
		customDownloadDestinationURL?.stopAccessingSecurityScopedResource()
	}
}

extension FileTransferStore {
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
		customDownloadDestinationURL?.stopAccessingSecurityScopedResource()
		customDownloadDestinationURL = nil
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
		for session: ServerSession,
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
			session.printDebugInformation(
				toConsole: ConnectionSafetyStrings.FileTransfer.refusedBecauseCrowded(sender: nickname)
			)
			return nil
		}

		guard let controller = FileTransfer.receiver(
			for: session,
			center: self,
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
			SettingsKeys.FileTransfers.requestReplyAction.value,
			peerIsKnown: peerIsKnown,
			filesize: totalFilesize
		) {
			let destinationPath = downloadDestinationURL?.path

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

			controller.destinationAccessURL = customDownloadDestinationURL
			controller.open(withPath: destinationPath)
		}

		return controller.uniqueIdentifier
	}

	/// Owns file preparation started by a synchronous menu or IRC command.
	func offerSender(
		for session: ServerSession, nickname: String, path: String, autoOpen: Bool,
		accessURL: URL? = nil, completion: @escaping (String?) -> Void = { _ in }
	) {
		let identifier = UUID()
		senderPreparations[identifier] = Task { [weak self] in
			guard let self else { return }
			let result = await addSender(for: session, nickname: nickname, path: path,
			                             autoOpen: autoOpen, accessURL: accessURL)
			senderPreparations[identifier] = nil
			guard !Task.isCancelled else { return }
			completion(result)
		}
	}

	func addSender(
		for session: ServerSession,
		nickname: String,
		path: String,
		autoOpen: Bool,
		accessURL: URL? = nil
	) async -> String? {
		let startupIdentifier = session.startup.identifier
		guard let controller = await FileTransfer.sender(
			for: session,
			center: self,
			nickname: nickname,
			path: path,
			accessURL: accessURL
		) else {
			return nil
		}

		guard !Task.isCancelled, !session.isTerminating, session.startup.identifier == startupIdentifier else {
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

	func sessionWillBeDestroyed(_ notification: Notification) {
		guard let session = notification.object as? ServerSession else { return }
		removeFileTransfers(model.transfers.filter { $0.session === session })
	}

	func clearStoppedTransfers() {
		removeFileTransfers(model.stoppedTransfers)
	}

	func perform(_ action: FileTransferAction, on identifiers: Set<String>) {
		let transfers = model.transfers(with: identifiers)
		switch action {
		case .start:
			startTransfers(transfers)
		case .downloadTo:
			chooseDestination(for: transfers)
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
	func respondToNotification(for identifier: String, sessionIdentifier: String?, accept: Bool) -> Bool {
		guard let transfer = notifiedTransfer(identifier, of: sessionIdentifier) else { return false }
		model.reveal(identifier)
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
	func declineNotification(for identifier: String, sessionIdentifier: String?) -> Bool {
		guard let transfer = notifiedTransfer(identifier, of: sessionIdentifier) else { return false }
		if transfer.isSender == false, transfer.transferStatus == .stopped {
			removeFileTransfers([transfer])
		} else {
			transfer.closeAndPostNotification(false)
		}
		return true
	}

	/// The transfer a notification names, if it is still listed and still
	/// belongs to the connection the notification was posted for.
	private func notifiedTransfer(_ identifier: String, of sessionIdentifier: String?) -> FileTransfer? {
		guard let transfer = fileTransfer(withUniqueIdentifier: identifier),
		      sessionIdentifier == nil || sessionIdentifier == transfer.sessionId
		else {
			return nil
		}

		return transfer
	}

	func updateMaintenanceTimer() {
		guard model.activeTransfers.isEmpty == false else {
			maintenanceTimer.stop()

			return
		}

		maintenanceTimer.startIfIdle(FileTransferConstants.maintenanceInterval, repeats: true)
	}

	func onMaintenanceTimer() {
		model.activeTransfers.forEach { $0.onMaintenanceTimer() }
	}

	private func startTransfers(_ transfers: [FileTransfer]) {
		let destination = downloadDestinationURL
		var pending: [FileTransfer] = []

		for transfer in transfers where transfer.canStart {
			if transfer.isSender {
				transfer.open()
			} else if let path = transfer.path {
				guard claimRoom(for: transfer, at: path) else { continue }
				transfer.open()
			} else if let destination {
				guard claimRoom(for: transfer, at: destination.path) else { continue }
				transfer.destinationAccessURL = customDownloadDestinationURL
				transfer.open(withPath: destination.path)
			} else {
				pending.append(transfer)
			}
		}

		chooseDestination(for: pending)
	}

	private func chooseDestination(for transfers: [FileTransfer]) {
		let pending = transfers.filter { $0.isSender == false && $0.canStart && $0.path == nil }
		guard pending.isEmpty == false else { return }
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
			guard (error as? CocoaError)?.code != .userCancelled else { return }
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
	private func claimRoom(for transfer: FileTransfer, at path: String) -> Bool {
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

	private func removeFileTransfers(_ transfers: [FileTransfer]) {
		guard transfers.isEmpty == false else { return }

		for transfer in transfers {
			transfer.prepareForPermanentDestruction()
		}

		model.remove(transfers)
	}
}
