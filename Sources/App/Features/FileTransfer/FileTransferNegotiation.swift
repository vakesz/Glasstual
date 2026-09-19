// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2018 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation
import os

/** What the negotiation a transfer is in the middle of has in flight.

 Every field is the negotiation's own: the run its tasks belong to, the tasks
 themselves, the router mapping it opened, the actor moving the bytes and the
 factory it reserves descriptors through. None of it is anything the row, the
 list or the center has business in, so it travels as one value rather than as
 eleven properties on an observed class — and what one negotiation started is
 dropped in one call instead of by a list of cancels kept in step by hand in
 two places. */
struct FileTransferNegotiation {
	/** The run the tasks below belong to.

	 A transfer that was stopped and started again is a new run, and the timeouts
	 and steps the old one left behind must not report into it. */
	var sessionID = UUID()
	/// Reserving the destination file, before any negotiation can name it.
	var filePreparationTask: Task<Void, Never>?
	/// The step the negotiation is waiting on: an offset commit, or the size of
	/// the partial a RESUME would continue from.
	var negotiationTask: Task<Void, Never>?
	/// Gives up on an unanswered RESUME without truncating the partial file.
	var resumeRequestTimeout: Task<Void, Never>?
	/// Gives up on a reverse offer the peer never answered, which would
	/// otherwise hold a listening port open for good.
	var offerTimeout: Task<Void, Never>?
	/// Follows the ``DCCTransfer`` actor's events back onto the main actor.
	var transferEvents: Task<Void, Never>?
	/// Set when resuming failed, so the next start begins the file again in a
	/// new reservation instead of asking the peer to resume once more.
	var restartsFromBeginning = false
	/// The actor moving the bytes, while there is one.
	var transfer: DCCTransfer?
	var portMapping: PortMapper?
	let portMapperNotifications = NotificationSubscriptions()
	/// How a descriptor is opened. The real thing, except in tests.
	var fileFactory: @Sendable (URL, Bool, URL?) async throws -> DCCTransferFile = { url, receiving, accessURL in
		try await DCCTransferFile.open(url: url, receiving: receiving, accessURL: accessURL)
	}

	/// Drops the steps and deadlines this negotiation has in flight, so nothing
	/// it started can report into a transfer that has stopped.
	mutating func cancelPendingWork() {
		filePreparationTask?.cancel()
		filePreparationTask = nil
		negotiationTask?.cancel()
		negotiationTask = nil
		resumeRequestTimeout?.cancel()
		resumeRequestTimeout = nil
		offerTimeout?.cancel()
		offerTimeout = nil
	}

	/** Gives the router mapping back.

	 An open NAT-PMP mapping keeps its mapper alive so that mDNSResponder's
	 callback context stays valid, so dropping the transfer does not release the
	 mapping: it has to be closed. */
	mutating func closePortMapping() {
		guard let portMapping else { return }

		portMapperNotifications.cancelAll()
		self.portMapping = nil
		portMapping.close()
	}

	/// Everything the negotiation holds, for a transfer that is going away. The
	/// actor is handed back because cancelling it is a suspension the caller has
	/// to order against the rest of its teardown.
	mutating func tearDown() -> DCCTransfer? {
		cancelPendingWork()
		transferEvents?.cancel()
		transferEvents = nil
		portMapperNotifications.cancelAll()
		closePortMapping()
		defer { transfer = nil }
		return transfer
	}
}

// MARK: - Starting

extension FileTransfer {
	func open() {
		open(withPath: nil)
	}

	func open(withPath path: String?) {
		guard canStart else { return }
		if self.path == nil {
			self.path = path
		}

		guard session?.isLoggedIn == true else {
			closeWithSessionDisconnectedErrorImmediately()
			return
		}

		if isSender {
			// A new offer needs a new agreement. SEND answering the current
			// reverse offer bypasses this entry point and retains its offset.
			isResume = false
			processedFilesize = 0
			openTransfer()
		} else {
			let restart = negotiation.restartsFromBeginning
			negotiation.restartsFromBeginning = false
			if restart {
				isResume = false
				processedFilesize = 0
			}
			transferStatus = .initializing
			let run = negotiation.sessionID
			negotiation.filePreparationTask = Task { [weak self] in
				guard let self else { return }
				await claimDestinationFilename()
				guard isCurrent(run), ownedFile != nil else { return }
				negotiation.filePreparationTask = nil
				if restart {
					openTransfer()
				} else {
					sendTransferResumeRequestToSession()
				}
			}
		}
	}

	/** Fails a resume in a way Try Again can get past.

	 The descriptor on the partial is let go of now, since the next attempt will
	 not write into it, and that attempt starts the file over. */
	func closeForRestart(with failure: FileTransferFailure) {
		releaseOwnedFile()
		negotiation.restartsFromBeginning = true
		close(with: failure)
	}

	/// Reserves once with O_EXCL. Retries keep the descriptor and partial bytes;
	/// the local suffix never changes the filename used in DCC negotiation.
	func claimDestinationFilename() async {
		guard ownedFile == nil, let path else { return }
		let run = negotiation.sessionID
		do {
			let url = URL(fileURLWithPath: path).appendingPathComponent(wireFilename)
			let file = try await negotiation.fileFactory(
				url, true, destinationAccessURL ?? url.deletingLastPathComponent()
			)
			guard isCurrent(run), ownedFile == nil else {
				await file.close()
				return
			}
			takeOwnership(of: file)
			filename = (file.path as NSString).lastPathComponent
		} catch {
			guard isCurrent(run) else { return }
			/* The folder is forgotten with the failure. Keeping it made every
			 Try Again write into the same unwritable folder instead of asking
			 for another one. */
			self.path = nil
			close(with: FileTransferFailure(.fileUnwritable))
		}
	}

	private func openTransfer() {
		switch (isSender, isReversed) {
		case (true, true):
			closeAndPostNotification(false)
			resetProperties(keepingOffset: isResume)
			transferStatus = .initializing
			updateIPAddress()
		case (true, false), (false, true):
			openConnectionAsServer()
		case (false, false):
			openConnectionToHost()
		}
	}

	private func openConnectionToHost() {
		closeAndPostNotification(false)
		resetProperties(keepingOffset: isResume)
		transferStatus = .connecting

		guard !hostAddress.isEmpty, hostPort != 0 else {
			fileTransferLogger.error("DCC connection has an invalid host address or port")
			close(with: .connectionUnavailable)
			return
		}

		guard let file = prepareTransferFile() else { return }

		startTransfer(with: transferConfig(
			endpoint: .connect(
				host: hostAddress,
				port: hostPort,
				interfaceName: SettingsKeys.FileTransfers.ipAddressInterfaceName.storedValue,
				timeout: .seconds(FileTransferLimits.connectTimeout)
			),
			file: file
		))
		disableSystemSleep()
	}

	private func openConnectionAsServer() {
		closeAndPostNotification(false)
		resetProperties(keepingOffset: isResume)
		transferStatus = .initializing

		let portRangeStart = SettingsKeys.FileTransfers.portRangeStart.value
		let portRangeEnd = SettingsKeys.FileTransfers.portRangeEnd.value
		guard portRangeStart != 0, portRangeStart <= portRangeEnd else {
			close(with: .noListeningPort)
			return
		}

		guard let file = prepareTransferFile() else { return }

		startTransfer(with: transferConfig(
			endpoint: .listen(portRange: portRangeStart ... portRangeEnd),
			file: file
		))
		disableSystemSleep()
	}

	private func transferConfig(
		endpoint: DCCEndpoint,
		file: DCCTransferFile
	) -> DCCTransfer.Config {
		DCCTransfer.Config(
			role: isSender ? .sender : .receiver,
			endpoint: endpoint,
			file: file,
			fileSize: totalFilesize,
			resumeOffset: processedFilesize,
			expectedPeerAddress: expectedPeerAddress,
			sendTimeout: .seconds(FileTransferLimits.sendTimeout)
		)
	}

	/** The address an inbound connection has to come from.

	 A reverse DCC names the peer in its own offer, so that address is the
	 answer. A plain `DCC SEND` negotiates none — we listen, and the peer
	 announces itself by arriving — and there is nothing to compare against.

	 The peer's hostmask is not that answer, however literal it looks. The
	 address the server publishes is the one the peer reached *the server*
	 from: a dual-stack peer that registered over IPv6 dials out over IPv4, a
	 privacy address rotates under them, and behind NAT the server sees the
	 gateway rather than the host. Refusing the transfer on any of those is a
	 failure the user cannot do anything about, so only an address the offer
	 itself named is checked. */
	private var expectedPeerAddress: String {
		guard isActingAsServer else {
			return ""
		}

		return hostAddress
	}

	/// The file this transfer reads from, or the one it writes into.
	private func prepareTransferFile() -> DCCTransferFile? {
		guard let ownedFile else {
			close(with: .sourceFileUnreadable)
			return nil
		}

		return ownedFile
	}

	private func resetProperties(keepingOffset: Bool) {
		completion = nil
		if keepingOffset == false {
			processedFilesize = 0
		}
		currentRecord = 0
		errorMessageDescription = nil
		speedRecords.removeAll(keepingCapacity: true)
	}
}

// MARK: - The DCC negotiation this transfer answers

extension FileTransfer {
	func didReceiveResumeRequest(_ proposedPosition: UInt64) {
		guard isSender, proposedPosition > 0, totalFilesize >= proposedPosition,
		      [.waitingForReceiverToAccept, .isListeningAsSender].contains(transferStatus) else { return }
		let run = negotiation.sessionID
		let transfer = negotiation.transfer
		negotiation.negotiationTask?.cancel()
		negotiation.negotiationTask = Task { [weak self] in
			if let transfer, await transfer.commitResumeOffset(proposedPosition) == false {
				return
			}
			guard let self, isCurrent(run) else { return }
			isResume = true
			processedFilesize = proposedPosition
			sendTransferResumeAcceptToSession()
		}
	}

	func didReceiveResumeAccept(_ proposedPosition: UInt64) {
		/* An accept is only ever an answer to a resume this transfer asked for.
		 One that arrives at any other moment would move the offset into a file
		 nothing has claimed. */
		guard !isSender, transferStatus == .waitingForResumeAccept else { return }

		negotiation.resumeRequestTimeout?.cancel()
		negotiation.resumeRequestTimeout = nil

		guard proposedPosition > 0, proposedPosition <= totalFilesize, processedFilesize == proposedPosition else {
			closeForRestart(with: .invalidResumePosition)
			return
		}

		isResume = true
		openTransfer()
	}

	func didReceiveSendRequest(_ hostAddress: String, hostPort: UInt16) {
		guard isSender, isReversed, transferStatus == .waitingForReceiverToAccept else { return }
		self.hostAddress = hostAddress
		self.hostPort = hostPort
		transferStatus = .connecting
		let step = negotiation.negotiationTask
		let run = negotiation.sessionID
		Task { [weak self] in
			await step?.value
			guard let self, isCurrent(run), transferStatus == .connecting else { return }
			openConnectionToHost()
		}
	}

	func sendTransferRequestToSession() {
		guard let session else { return }

		if isSender {
			if isReversed {
				/* Offering a reverse DCC without a token is a malformed request
				 rather than a transfer the peer can complete. Report it. */
				guard buildTransferToken() else {
					fileTransferLogger.error("Could not mint a reverse DCC transfer token")
					close(with: .connectionUnavailable)
					return
				}

				session.sendFile(
					peerNickname,
					port: 0,
					filename: wireFilename,
					filesize: totalFilesize,
					token: transferToken
				)
			} else {
				session.sendFile(
					peerNickname,
					port: hostPort,
					filename: wireFilename,
					filesize: totalFilesize,
					token: nil
				)
			}
		} else if isReversed {
			session.sendFile(
				peerNickname,
				port: hostPort,
				filename: wireFilename,
				filesize: totalFilesize,
				token: transferToken
			)
		}
	}

	/** What the RESUME wait does when it runs out.

	 Cancellation is not the only way the wait becomes stale. The transfer may
	 have been stopped and started again during the sleep, so the accept it is
	 waiting on belongs to a newer session; or the `DCC ACCEPT` may have arrived
	 and moved the transfer on, which is what clears the wait in the first place.
	 Either way there is nothing left for the timeout to fail, and without these
	 guards the sleep killed a transfer that had just begun.

	 A step of its own so that the guards can be exercised without waiting out a
	 real timeout.

	 - Parameter sessionID: The session the wait was started for.
	 - Returns: Whether the timeout closed the transfer. */
	@discardableResult
	func resumeTimeoutExpired(for sessionID: UUID) -> Bool {
		guard negotiation.sessionID == sessionID, transferStatus == .waitingForResumeAccept else {
			return false
		}

		negotiation.resumeRequestTimeout = nil
		// A refused resume must not truncate the partial download.
		closeForRestart(with: .resumeNotAnswered)

		return true
	}

	/// Mints the token that identifies a reverse-DCC offer.
	///
	/// The token is the only thing tying an inbound connection on the listening
	/// port to this offer, so it is drawn from the system CSPRNG over the full
	/// 64-bit range rather than the four decimal digits a third party could
	/// enumerate during the window the port is open.
	private func buildTransferToken() -> Bool {
		for _ in 0 ..< 300 {
			let candidate = String(UInt64.random(in: 1 ... UInt64.max))
			if center?.fileTransferExists(withToken: candidate) != true {
				transferToken = candidate
				return true
			}
		}

		transferToken = nil
		return false
	}

	private func sendTransferResumeRequestToSession() {
		guard let ownedFile else { return }
		transferStatus = .initializing
		let run = negotiation.sessionID
		let stopping = stopTask
		negotiation.negotiationTask = Task { [weak self] in
			await stopping?.value
			do {
				let size = try await ownedFile.size()
				guard let self, isCurrent(run) else { return }
				guard size <= totalFilesize else {
					closeForRestart(with: .invalidResumePosition)
					return
				}
				processedFilesize = size
				isResume = false
				if size == 0 {
					openTransfer()
					return
				}
				requestResume(position: size)
			} catch {
				/* The partial was moved, deleted or replaced since it was
				 claimed, so there is nothing left to resume into. */
				guard let self, isCurrent(run) else { return }
				closeForRestart(with: .invalidResumePosition)
			}
		}
	}

	private func requestResume(position: UInt64) {
		negotiation.resumeRequestTimeout?.cancel()
		let run = negotiation.sessionID
		negotiation.resumeRequestTimeout = Task { [weak self] in
			do {
				try await Task.sleep(for: .seconds(FileTransferLimits.resumeAcceptTimeout))
			} catch {
				return
			}

			guard Task.isCancelled == false, let self else { return }
			resumeTimeoutExpired(for: run)
		}
		transferStatus = .waitingForResumeAccept
		session?.sendFileResume(
			peerNickname,
			port: isReversed ? 0 : hostPort,
			filename: wireFilename,
			filesize: position,
			token: isReversed ? transferToken : nil
		)
	}

	private func sendTransferResumeAcceptToSession() {
		session?.sendFileResumeAccept(
			peerNickname,
			port: isReversed ? 0 : hostPort,
			filename: wireFilename,
			filesize: processedFilesize,
			token: isReversed ? transferToken : nil
		)
	}
}
