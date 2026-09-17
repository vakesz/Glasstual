// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2018 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
import CocoaExtensions
import Foundation
import os

private struct FileTransferPeerNicknameChange: NotificationCenter.MainActorMessage {
	typealias Subject = Client

	static var name: Notification.Name {
		.ClientUserNicknameChanged
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
	subsystem: Bundle.main.bundleIdentifier ?? "Glasstual",
	category: "FileTransfer"
)

enum FileTransferStatus: UInt, Sendable {
	case complete
	case connecting
	case fatalError
	case initializing
	case isListeningAsReceiver
	case isListeningAsSender
	case mappingListeningPort
	case receiving
	case recoverableError
	case sending
	case stopped
	case waitingForLocalIPAddress
	case waitingForReceiverToAccept
	case waitingForResumeAccept
}

/** What each status means to the rest of the feature.

 The same handful of status groups used to be spelled out as a set literal at
 every place that asked — the receiver limit, the row list, the close path, the
 address lookup — and a new status had to be remembered in all of them. */
extension FileTransferStatus {
	/// Bytes are moving right now.
	var isActive: Bool {
		self == .sending || self == .receiving
	}

	/// The two ends are still agreeing how to reach each other. No byte of the
	/// file has crossed yet, but the transfer is under way.
	var isNegotiating: Bool {
		switch self {
		case .connecting, .initializing, .isListeningAsReceiver, .isListeningAsSender,
		     .mappingListeningPort, .waitingForLocalIPAddress, .waitingForReceiverToAccept,
		     .waitingForResumeAccept:
			true
		case .complete, .fatalError, .receiving, .recoverableError, .sending, .stopped:
			false
		}
	}

	/// Whether the transfer is spending resources: a slot against the receiver
	/// limit, room on the destination volume, a tick of the maintenance timer.
	var isRunning: Bool {
		isActive || isNegotiating
	}

	/// The transfer reached an answer. `stopped` is not one: it is a transfer
	/// that has not been started.
	var isFinished: Bool {
		self == .complete || self == .fatalError || self == .recoverableError
	}

	/// The phase an address lookup is allowed to move the transfer on from.
	var isAwaitingAddress: Bool {
		self == .initializing || self == .mappingListeningPort || self == .waitingForLocalIPAddress
	}

	/// The transfer is idle, and the reason it is idle is one a retry can get
	/// past. Every place that offers to start a transfer asks this, so they
	/// cannot drift apart.
	var canRetry: Bool {
		self == .stopped || self == .recoverableError
	}
}

/// Owns one DCC file transfer: what the user sees of it, and the negotiation
/// that surrounds it.
///
/// The bytes themselves belong to a ``DCCTransfer`` actor. The controller
/// starts one, follows its `AsyncStream` of events on the main actor, and
/// turns them into the status the dialog, Client and the maintenance timer
/// read -- all of which are main-actor too.
@MainActor
@Observable
final class FileTransfer: ClientScoped {
	var client: Client?
	var clientId: String?

	/// Whether the bytes continue a partly transferred file, which is what
	/// decides if a restart keeps ``processedFilesize`` or zeroes it.
	var isResume = false
	var isReversed = false
	var isSender = false
	var totalFilesize: UInt64 = 0
	var processedFilesize: UInt64 = 0
	var currentRecord: UInt64 = 0
	var errorMessageDescription: String?
	var path: String?
	var filename = ""
	var wireFilename = ""
	var hostAddress = ""
	var peerNickname = ""
	var transferToken: String?
	var uniqueIdentifier = UUID().uuidString
	var hostPort: UInt16 = 0

	var speedRecords: [UInt64] = []
	var transferStatus: FileTransferStatus = .stopped

	/// The descriptor this transfer reads from or writes into, and the
	/// authority for all byte I/O and resume validation.
	var ownedFile: DCCTransferFile?

	/** The directory the user let us reach, kept after the descriptor is gone.

	 The row still has to open and reveal the file once the transfer is closed,
	 which is why this outlives ``ownedFile`` rather than being read off it. An
	 inactive capability URL, not an outstanding security-scope lease. */
	var fileAccessURL: URL?
	var destinationAccessURL: URL?
	var negotiationTask: Task<Void, Never>?
	var filePreparationTask: Task<Void, Never>?
	var fileFactory: @Sendable (URL, Bool, URL?) async throws -> DCCTransferFile = { url, receiving, accessURL in
		try await DCCTransferFile.open(url: url, receiving: receiving, accessURL: accessURL)
	}

	var stopTask: Task<Void, Never>?
	var sessionID = UUID()
	var completion: DCCTransfer.Completion?
	var portMapping: PortMapper?
	var transfer: DCCTransfer?
	var transferEvents: Task<Void, Never>?
	/// Set when resuming failed, so the next start begins the file again in a
	/// new reservation instead of asking the peer to resume once more.
	var restartsFromBeginning = false
	/// Gives up on an unanswered RESUME without truncating the partial file.
	var resumeRequestTimeout: Task<Void, Never>?
	var offerTimeout: Task<Void, Never>?
	var transferProgressHandler: NSObjectProtocol?
	var lifecycleNotifications = NotificationSubscriptions()
	var portMapperNotifications = NotificationSubscriptions()
	private var peerNicknameObservation: NotificationCenter.ObservationToken?

	var canStart: Bool {
		transferStatus.canRetry
	}

	private init(client: Client) {
		self.client = client
		clientId = client.uniqueIdentifier
		lifecycleNotifications.observe(.ClientDidDisconnect, object: client) { [weak self] notification in
			self?.clientDisconnected(notification)
		}
		/* A NICK must update the destination before another main-actor operation
		 can send an offer, including the turn that resumes file preparation. */
		peerNicknameObservation = NotificationCenter.default
			.addObserver(of: client, for: FileTransferPeerNicknameChange.self) { [weak self] change in
				self?.peerNicknameChanged(from: change.oldNickname, to: change.newNickname)
			}
	}

	func stopObservingPeerNicknameChanges() {
		guard let peerNicknameObservation else { return }
		NotificationCenter.default.removeObserver(peerNicknameObservation)
		self.peerNicknameObservation = nil
	}

	isolated deinit {
		filePreparationTask?.cancel()
		negotiationTask?.cancel()
		resumeRequestTimeout?.cancel()
		offerTimeout?.cancel()
		transferEvents?.cancel()
		lifecycleNotifications.cancelAll()
		stopObservingPeerNicknameChanges()
		portMapperNotifications.cancelAll()
		/* An open NAT-PMP mapping keeps its mapper alive so that mDNSResponder's
		 callback context stays valid, so dropping the controller is not enough
		 to release the router mapping: it has to be closed here. */
		portMapping?.close()
		portMapping = nil
		if let transferProgressHandler {
			ProcessInfo.processInfo.endActivity(transferProgressHandler)
		}
		let transfer = transfer
		let file = ownedFile
		let stopping = stopTask
		Task {
			await stopping?.value
			await transfer?.cancel()
			await file?.close()
		}
	}

	static func receiver(
		for client: Client,
		nickname: String,
		address hostAddress: String,
		port hostPort: UInt16,
		filename: String,
		filesize totalFilesize: UInt64,
		token transferToken: String?
	) -> FileTransfer? {
		let wireFilename = filename.safeFilename
		guard !wireFilename.isEmpty else { return nil }
		let controller = FileTransfer(client: client)

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
		for client: Client,
		nickname: String,
		path: String,
		accessURL: URL? = nil
	) async -> FileTransfer? {
		await sender(for: client, nickname: nickname, path: path, accessURL: accessURL) { url, receiving, accessURL in
			try await DCCTransferFile.open(url: url, receiving: receiving, accessURL: accessURL)
		}
	}

	static func sender(
		for client: Client,
		nickname: String,
		path: String,
		accessURL: URL? = nil,
		fileFactory: @Sendable (URL, Bool, URL?) async throws -> DCCTransferFile
	) async -> FileTransfer? {
		let controller = FileTransfer(client: client)
		controller.isReversed = Preferences.FileTransfers.requestsAreReversed.value
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

	var transferCenter: FileTransferCenter {
		AppServices.fileTransfers
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
	func isCurrent(_ session: UUID) -> Bool {
		Task.isCancelled == false && sessionID == session
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
		portMapperNotifications.cancelAll()
		releaseOwnedFile()
	}

	func close() {
		closeAndPostNotification(true)
	}

	func closeAndPostNotification(_ postNotification: Bool) {
		filePreparationTask?.cancel()
		filePreparationTask = nil
		negotiationTask?.cancel()
		negotiationTask = nil
		resumeRequestTimeout?.cancel()
		resumeRequestTimeout = nil
		offerTimeout?.cancel()
		offerTimeout = nil

		stopTransfer()
		/* A recoverable failure keeps its descriptor and its partial bytes: that
		 is the whole of what Start Transfer has left to resume from. */
		if transferStatus.isFinished, transferStatus.canRetry == false {
			releaseOwnedFile()
		}
		closePortMapping()

		if transferStatus.isFinished == false {
			transferStatus = .stopped
		}

		if postNotification {
			postCompletionNotificationIfNeeded()
		}

		transferCenter.updateMaintenanceTimer()
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

	func closeWithClientDisconnectedErrorImmediately() {
		close(with: .notConnectedToIRC)
	}

	func peerNicknameChanged(from oldNickname: String, to newNickname: String) {
		guard let client,
		      client.supportInfo.casefoldString(peerNickname) == client.supportInfo.casefoldString(oldNickname)
		else {
			return
		}
		peerNickname = newNickname
	}

	/// A transfer still negotiating cannot finish without the connection it was
	/// negotiated over; one already moving bytes is on its own socket.
	func clientDisconnected(_: Notification) {
		guard transferStatus.isNegotiating else { return }
		closeWithClientDisconnectedErrorImmediately()
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
		guard let client else { return }

		let type: NotificationEvent
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

		client.notifyFileTransfer(
			type,
			nickname: peerNickname,
			filename: filename,
			filesize: totalFilesize,
			requestIdentifier: uniqueIdentifier
		)
	}
}

/// Which way a transfer runs.
nonisolated enum FileTransferDirection: Sendable {
	case incoming
	case outgoing

	/// The line under a running transfer's progress bar.
	func progressNotice(
		processedSize: String,
		totalSize: String,
		speed: String,
		peerNickname: String,
		timeRemaining: String?
	) -> String {
		let resource: LocalizedStringResource = switch (self, timeRemaining) {
		case let (.incoming, timeRemaining?):
			.FileTransfers.ofSReceivedFromRemaining(processedSize, totalSize, speed, peerNickname, timeRemaining)
		case (.incoming, nil):
			.FileTransfers.ofSReceived(processedSize, totalSize, speed, peerNickname)
		case let (.outgoing, timeRemaining?):
			.FileTransfers.ofSSentToRemaining(processedSize, totalSize, speed, peerNickname, timeRemaining)
		case (.outgoing, nil):
			.FileTransfers.ofSSent(processedSize, totalSize, speed, peerNickname)
		}

		return String(localized: resource)
	}
}

/// Why a transfer stopped.
nonisolated enum FileTransferFailure: Equatable, Sendable {
	case connectionUnavailable
	case connectTimeout
	case fileHandlerFailed
	case invalidResumePosition
	case noListeningPort
	case notConnectedToIRC
	case oversizedTransfer
	case peerClosedConnection
	/// The peer never answered a RESUME.
	case resumeNotAnswered
	case sourceFileUnreadable
	case sourceIPAddressUnknown
	case storageFull
	case stalled
	/// A transport error that arrived with its own description. Only
	/// ``DCCTransferError/network(_:)`` carries one; every other transport
	/// failure maps to a case above, which is what gives it localized copy.
	case underlying(String)

	init(_ error: DCCTransferError) {
		switch error {
		case .badParameter, .rejectedPeerAddress:
			self = .connectionUnavailable
		case .closedByPeer:
			self = .peerClosedConnection
		case .connectTimeout:
			self = .connectTimeout
		case .fileUnreadable:
			self = .sourceFileUnreadable
		case .fileUnwritable:
			self = .fileHandlerFailed
		case let .network(description):
			self = .underlying(description)
		case .noOpenPort:
			self = .noListeningPort
		case .oversizedTransfer:
			self = .oversizedTransfer
		case .storageFull:
			self = .storageFull
		case .stalled:
			self = .stalled
		}
	}

	/// What the row says went wrong.
	func message(peerNickname: String) -> String {
		let resource = switch self {
		case .connectionUnavailable:
			LocalizedStringResource.FileTransfers.transferWithFailedCouldNotEstablish(peerNickname)
		case .connectTimeout:
			LocalizedStringResource.FileTransfers.transferWithFailedNoAnswer(peerNickname)
		case .fileHandlerFailed:
			LocalizedStringResource.FileTransfers.transferWithFailedFileHandlerThrew(peerNickname)
		case .invalidResumePosition:
			LocalizedStringResource.FileTransfers.transferWithFailedProposedResumePosition(peerNickname)
		case .noListeningPort:
			LocalizedStringResource.FileTransfers.transferWithFailedThereIsNo(peerNickname)
		case .notConnectedToIRC:
			LocalizedStringResource.FileTransfers.transferWithFailedYouAreNot(peerNickname)
		case .oversizedTransfer:
			LocalizedStringResource.FileTransfers.transferFromFailedBecauseTheSender(peerNickname)
		case .peerClosedConnection:
			LocalizedStringResource.FileTransfers.transferWithFailedPeerClosed(peerNickname)
		case .resumeNotAnswered:
			LocalizedStringResource.FileTransfers.transferWithFailedResumeNotAnswered(peerNickname)
		case .sourceFileUnreadable:
			LocalizedStringResource.FileTransfers.transferWithFailedCouldNotRead(peerNickname)
		case .sourceIPAddressUnknown:
			LocalizedStringResource.FileTransfers.transferWithFailedUnknownSourceIp(peerNickname)
		case .storageFull:
			LocalizedStringResource.FileTransfers.transferWithFailedNoSpaceLeft(peerNickname)
		case .stalled:
			LocalizedStringResource.FileTransfers.transferWithFailedStalled(peerNickname)
		case let .underlying(description):
			LocalizedStringResource.FileTransfers.transferWithFailed(peerNickname, description)
		}

		return String(localized: resource)
	}
}

nonisolated extension FileTransferStatus {
	/** How an idle or negotiating transfer reads in its row.

	 Every step between Start and the first byte -- mapping a port, working out
	 this Mac's address, opening the socket -- is one wait from the user's side,
	 and naming each of them separately told them nothing they could act on. */
	func notice(direction: FileTransferDirection, peerNickname: String) -> String? {
		let resource: LocalizedStringResource? = switch (self, direction) {
		case (.stopped, .incoming):
			.FileTransfers.transferFromIsStopped(peerNickname)
		case (.stopped, .outgoing):
			.FileTransfers.transferToIsStopped(peerNickname)
		case (.initializing, _), (.mappingListeningPort, _), (.waitingForLocalIPAddress, _):
			.FileTransfers.preparingTheTransfer
		case (.isListeningAsSender, _), (.waitingForReceiverToAccept, _):
			.FileTransfers.transferToIsReadyWaiting(peerNickname)
		case (.isListeningAsReceiver, _):
			.FileTransfers.transferFromIsReady(peerNickname)
		case (.complete, .incoming):
			.FileTransfers.transferFromIsComplete(peerNickname)
		case (.complete, .outgoing):
			.FileTransfers.transferToIsComplete(peerNickname)
		case (.connecting, _):
			.FileTransfers.statusWhileConnecting(peerNickname)
		case (.waitingForResumeAccept, _):
			.FileTransfers.transferFromWaitingForResponse(peerNickname)
		case (.fatalError, _), (.recoverableError, _), (.receiving, _), (.sending, _):
			nil
		}

		return resource.map { String(localized: $0) }
	}
}
