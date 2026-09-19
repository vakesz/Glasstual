// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2018 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
import CocoaExtensions
import Foundation
import os

private struct FileTransferPeerNicknameChange: NotificationCenter.MainActorMessage {
	typealias Subject = ServerSession

	static var name: Notification.Name {
		.serverSessionUserNicknameChanged
	}

	let oldNickname: String
	let newNickname: String

	static func makeMessage(_ notification: Notification) -> Self? {
		guard let oldNickname = notification.userInfo?["oldNickname"] as? String,
		      let newNickname = notification.userInfo?["newNickname"] as? String
		else { return nil }
		return Self(oldNickname: oldNickname, newNickname: newNickname)
	}
}

enum FileTransferLimits {
	static let speedRecordCount = 10
	static let connectTimeout: TimeInterval = 30
	static let sendTimeout: TimeInterval = 30
	static let resumeAcceptTimeout: TimeInterval = 10
	static let reverseOfferTimeout: Duration = .seconds(120)
}

let fileTransferLogger = Logger(
	subsystem: LogSubsystem.current,
	category: "FileTransfer"
)

/// Owns one DCC file transfer: what the user sees of it, and the negotiation
/// that surrounds it.
///
/// The bytes themselves belong to a ``DCCTransfer`` actor. The controller
/// starts one, follows its `AsyncStream` of events on the main actor, and
/// turns them into the status the dialog, ServerSession and the maintenance timer
/// read -- all of which are main-actor too.
@MainActor
@Observable
final class FileTransfer: SessionScoped {
	@ObservationIgnored var session: ServerSession?
	@ObservationIgnored var sessionId: String?

	/** The list this transfer is listed in.

	 It owns the maintenance timer every running transfer is ticked by, the one
	 address lookup they share, and the tokens already in use, none of which a
	 single transfer can answer for itself. Weak because the list owns the
	 transfer: this is the way back up, not a second owner. */
	@ObservationIgnored weak var center: FileTransferStore?

	/// Whether the bytes continue a partly transferred file, which is what
	/// decides if a restart keeps ``processedFilesize`` or zeroes it.
	@ObservationIgnored var isResume = false
	@ObservationIgnored var isReversed = false
	var isSender = false
	var totalFilesize: UInt64 = 0
	var processedFilesize: UInt64 = 0
	@ObservationIgnored var currentRecord: UInt64 = 0
	var errorMessageDescription: String?
	var path: String?
	var filename = ""
	@ObservationIgnored var wireFilename = ""
	@ObservationIgnored var hostAddress = ""
	var peerNickname = ""
	@ObservationIgnored var transferToken: String?
	let uniqueIdentifier = UUID().uuidString
	@ObservationIgnored var hostPort: UInt16 = 0

	var speedRecords: [UInt64] = []
	var transferStatus: FileTransferStatus = .stopped
	var completion: DCCTransfer.Completion?

	/// The descriptor this transfer reads from or writes into, and the
	/// authority for all byte I/O and resume validation.
	@ObservationIgnored var ownedFile: DCCTransferFile?

	/** The directory the user let us reach, kept after the descriptor is gone.

	 The row still has to open and reveal the file once the transfer is closed,
	 which is why this outlives ``ownedFile`` rather than being read off it. An
	 inactive capability URL, not an outstanding security-scope lease. */
	var fileAccessURL: URL?
	@ObservationIgnored var destinationAccessURL: URL?

	/// What the negotiation this transfer is in the middle of has in flight.
	/// Nothing outside the transfer itself reads any of it, and no view does,
	/// which is why a step starting or finishing does not redraw a row.
	@ObservationIgnored var negotiation = FileTransferNegotiation()

	@ObservationIgnored var stopTask: Task<Void, Never>?
	@ObservationIgnored var transferProgressHandler: NSObjectProtocol?
	@ObservationIgnored var lifecycleNotifications = NotificationSubscriptions()
	@ObservationIgnored private var peerNicknameObservation: NotificationCenter.ObservationToken?

	var canStart: Bool {
		transferStatus.canRetry
	}

	private init(session: ServerSession, center: FileTransferStore) {
		self.session = session
		self.center = center
		sessionId = session.uniqueIdentifier
		lifecycleNotifications.observe(.serverSessionDidDisconnect, object: session) { [weak self] notification in
			self?.sessionDisconnected(notification)
		}
		/* A NICK must update the destination before another main-actor operation
		 can send an offer, including the turn that resumes file preparation. */
		peerNicknameObservation = NotificationCenter.default
			.addObserver(of: session, for: FileTransferPeerNicknameChange.self) { [weak self] change in
				self?.peerNicknameChanged(from: change.oldNickname, to: change.newNickname)
			}
	}

	func stopObservingPeerNicknameChanges() {
		guard let peerNicknameObservation else { return }
		NotificationCenter.default.removeObserver(peerNicknameObservation)
		self.peerNicknameObservation = nil
	}

	isolated deinit {
		lifecycleNotifications.cancelAll()
		stopObservingPeerNicknameChanges()
		let transfer = negotiation.tearDown()
		if let transferProgressHandler {
			ProcessInfo.processInfo.endActivity(transferProgressHandler)
		}
		let file = ownedFile
		let stopping = stopTask
		Task {
			await stopping?.value
			await transfer?.cancel()
			await file?.close()
		}
	}

	static func receiver(
		for session: ServerSession,
		center: FileTransferStore,
		nickname: String,
		address hostAddress: String,
		port hostPort: UInt16,
		filename: String,
		filesize totalFilesize: UInt64,
		token transferToken: String?
	) -> FileTransfer? {
		let wireFilename = filename.safeFilename
		guard !wireFilename.isEmpty else { return nil }
		let controller = FileTransfer(session: session, center: center)

		if let transferToken, !transferToken.isEmpty {
			controller.transferToken = transferToken
			controller.isReversed = true
		}

		controller.peerNickname = nickname
		controller.hostAddress = hostAddress
		controller.hostPort = hostPort
		controller.filename = filename
		controller.wireFilename = wireFilename
		controller.totalFilesize = totalFilesize
		return controller
	}

	static func sender(
		for session: ServerSession,
		center: FileTransferStore,
		nickname: String,
		path: String,
		accessURL: URL? = nil
	) async -> FileTransfer? {
		await sender(
			for: session, center: center, nickname: nickname, path: path, accessURL: accessURL
		) { url, receiving, accessURL in
			try await DCCTransferFile.open(url: url, receiving: receiving, accessURL: accessURL)
		}
	}

	static func sender(
		for session: ServerSession,
		center: FileTransferStore,
		nickname: String,
		path: String,
		accessURL: URL? = nil,
		fileFactory: @Sendable (URL, Bool, URL?) async throws -> DCCTransferFile
	) async -> FileTransfer? {
		let controller = FileTransfer(session: session, center: center)
		controller.isReversed = SettingsKeys.FileTransfers.requestsAreReversed.value
		controller.isSender = true
		controller.peerNickname = nickname
		controller.path = (path as NSString).deletingLastPathComponent
		controller.filename = (path as NSString).lastPathComponent
		controller.wireFilename = controller.filename.safeFilename

		guard let file = try? await fileFactory(URL(fileURLWithPath: path), false, accessURL) else { return nil }
		guard !Task.isCancelled else {
			await file.close()
			return nil
		}
		controller.takeOwnership(of: file)
		controller.totalFilesize = file.initialSize
		return controller
	}

	/// Takes the descriptor, and the directory reservation that came with it.
	func takeOwnership(of file: DCCTransferFile) {
		ownedFile = file
		fileAccessURL = file.accessURL
	}
}

// MARK: - Where the transfer's file is

extension FileTransfer {
	var isActingAsServer: Bool {
		isSender != isReversed
	}

	var filePath: String? {
		guard let path else { return nil }
		return (path as NSString).appendingPathComponent(filename)
	}

	var fileURL: URL? {
		filePath.map { URL(fileURLWithPath: $0) }
	}

	var localFile: FileTransferLocalFile? {
		fileURL.map { FileTransferLocalFile(url: $0, accessURL: fileAccessURL ?? $0) }
	}
}

// MARK: - Ordering the tasks a transfer leaves behind

extension FileTransfer {
	/** Chains `step` onto the transfer's stop sequence.

	 Tearing a transfer down means cancelling an actor and closing a descriptor,
	 both of which take an await. Two teardowns that overlap close a file the
	 other is still writing, so each one waits for the one before it. */
	func enqueueStop(_ step: @escaping @Sendable () async -> Void) {
		let stopping = stopTask
		stopTask = Task {
			await stopping?.value
			await step()
		}
	}

	/** Whether a task started for `session` still speaks for this transfer.

	 A transfer that was stopped and started again is a new session, and the
	 timeouts and negotiation steps the old one left behind must not report into
	 the transfer that replaced it. Cancellation is the other half of the same
	 question, which is why both are asked here. */
	func isCurrent(_ run: UUID) -> Bool {
		Task.isCancelled == false && negotiation.sessionID == run
	}
}

// MARK: - Progress

extension FileTransfer {
	/// Folds the last second's bytes into the rolling average the row's speed
	/// and time-remaining are read from.
	func onMaintenanceTimer() {
		guard transferStatus.isActive else {
			assertionFailure("Maintenance timer fired for an inactive transfer")
			return
		}

		speedRecords.append(currentRecord)
		if speedRecords.count > FileTransferLimits.speedRecordCount {
			speedRecords.removeFirst()
		}
		currentRecord = 0
	}
}

extension FileTransfer {
	func prepareForPermanentDestruction() {
		closeAndPostNotification(false)
		lifecycleNotifications.cancelAll()
		stopObservingPeerNicknameChanges()
		negotiation.portMapperNotifications.cancelAll()
		releaseOwnedFile()
	}

	func close() {
		closeAndPostNotification(true)
	}

	func closeAndPostNotification(_ postNotification: Bool) {
		negotiation.cancelPendingWork()
		stopTransfer()
		/* A recoverable failure keeps its descriptor and its partial bytes: that
		 is the whole of what Start Transfer has left to resume from. */
		if transferStatus.isFinished, transferStatus.canRetry == false {
			releaseOwnedFile()
		}
		negotiation.closePortMapping()

		if transferStatus.isFinished == false {
			transferStatus = .stopped
		}

		if postNotification {
			postCompletionNotificationIfNeeded()
		}

		center?.updateMaintenanceTimer()
		enableSystemSleep()
	}

	func close(
		with failure: FileTransferFailure,
		isFatalError: Bool = false
	) {
		errorMessageDescription = failure.message(peerNickname: peerNickname)
		transferStatus = isFatalError ? .fatalError : .recoverableError
		close()
	}

	func closeWithSessionDisconnectedErrorImmediately() {
		close(with: .notConnectedToIRC)
	}

	func peerNicknameChanged(from oldNickname: String, to newNickname: String) {
		guard let session,
		      session.supportInfo.casefoldString(peerNickname) == session.supportInfo.casefoldString(oldNickname)
		else {
			return
		}
		peerNickname = newNickname
	}

	/// A transfer still negotiating cannot finish without the connection it was
	/// negotiated over; one already moving bytes is on its own socket.
	func sessionDisconnected(_: Notification) {
		guard transferStatus.isNegotiating else { return }
		closeWithSessionDisconnectedErrorImmediately()
	}

	func disableSystemSleep() {
		transferProgressHandler = ProcessInfo.processInfo.beginActivity(
			options: .userInitiated,
			reason: "Transferring file"
		) as NSObjectProtocol
	}

	func releaseOwnedFile() {
		guard let file = ownedFile else { return }
		ownedFile = nil
		enqueueStop { await file.close() }
	}

	private func enableSystemSleep() {
		guard let transferProgressHandler else { return }

		ProcessInfo.processInfo.endActivity(transferProgressHandler)
		self.transferProgressHandler = nil
	}

	private func postCompletionNotificationIfNeeded() {
		guard let session else { return }

		let type: UserNotificationEvent
		switch (transferStatus, isSender) {
		case (.fatalError, true), (.recoverableError, true):
			type = .fileTransferSendFailed
		case (.fatalError, false), (.recoverableError, false):
			type = .fileTransferReceiveFailed
		case (.complete, true):
			type = .fileTransferSendSuccessful
		case (.complete, false):
			type = .fileTransferReceiveSuccessful
		default:
			return
		}

		session.notifyFileTransfer(
			type,
			nickname: peerNickname,
			filename: filename,
			filesize: totalFilesize,
			requestIdentifier: uniqueIdentifier
		)
	}
}
