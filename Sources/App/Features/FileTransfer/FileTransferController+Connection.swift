/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
 * Copyright (c) 2010 - 2018 Codeux Software, LLC & respective contributors.
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

// MARK: - Starting

extension FileTransferController {
	func open() {
		open(withPath: nil)
	}

	func open(withPath path: String?) {
		guard canStart else { return }
		if self.path == nil {
			self.path = path
		}

		guard client?.isLoggedIn == true else {
			closeWithClientDisconnectedErrorImmediately()
			return
		}

		if isSender {
			// A new offer needs a new agreement. SEND answering the current
			// reverse offer bypasses this entry point and retains its offset.
			isResume = false
			processedFilesize = 0
			openTransfer()
		} else {
			let restart = restartsFromBeginning
			restartsFromBeginning = false
			if restart {
				isResume = false
				processedFilesize = 0
			}
			transferStatus = .initializing
			let session = sessionID
			filePreparationTask = Task { [weak self] in
				guard let self else { return }
				await claimDestinationFilename()
				guard isCurrent(session), ownedFile != nil else { return }
				filePreparationTask = nil
				if restart {
					openTransfer()
				} else {
					sendTransferResumeRequestToClient()
				}
			}
		}
	}

	/** Fails a resume in a way Try Again can get past.

	 The descriptor on the partial is let go of now, since the next attempt will
	 not write into it, and that attempt starts the file over. */
	func closeForRestart(with failure: FileTransferFailure) {
		releaseOwnedFile()
		restartsFromBeginning = true
		close(with: failure)
	}

	/// Reserves once with O_EXCL. Retries keep the descriptor and partial bytes;
	/// the local suffix never changes the filename used in DCC negotiation.
	func claimDestinationFilename() async {
		guard ownedFile == nil, let path else { return }
		let session = sessionID
		do {
			let url = URL(fileURLWithPath: path).appendingPathComponent(wireFilename)
			let file = try await fileFactory(url, true, destinationAccessURL ?? url.deletingLastPathComponent())
			guard isCurrent(session), ownedFile == nil else {
				await file.close()
				return
			}
			takeOwnership(of: file)
			filename = (file.path as NSString).lastPathComponent
		} catch {
			guard isCurrent(session) else { return }
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

		startTransfer(with: transferConfiguration(
			endpoint: .connect(
				host: hostAddress,
				port: hostPort,
				interfaceName: Preferences.FileTransfers.ipAddressInterfaceName.storedValue,
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

		let portRangeStart = Preferences.FileTransfers.portRangeStart.value
		let portRangeEnd = Preferences.FileTransfers.portRangeEnd.value
		guard portRangeStart != 0, portRangeStart <= portRangeEnd else {
			close(with: .noListeningPort)
			return
		}

		guard let file = prepareTransferFile() else { return }

		startTransfer(with: transferConfiguration(
			endpoint: .listen(portRange: portRangeStart ... portRangeEnd),
			file: file
		))
		disableSystemSleep()
	}

	private func transferConfiguration(
		endpoint: DCCTransfer.Endpoint,
		file: DCCTransferFile
	) -> DCCTransfer.Configuration {
		DCCTransfer.Configuration(
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

// MARK: - Listening, port mapping and this Mac's address

extension FileTransferController {
	func listeningServerDidStart(on port: UInt16) {
		guard transferStatus == .initializing else {
			assertionFailure("Listener started in an invalid transfer state")
			return
		}

		hostPort = port
		let mapper = PortMapper(port: port)
		mapper.mapTCP = true
		mapper.mapUDP = false
		mapper.desiredPublicPort = port
		portMapping = mapper

		portMapperNotifications.cancelAll()
		portMapperNotifications.observe(.portMapperDidChange, object: mapper) { [weak self] notification in
			self?.portMapperDidFinishWork(notification)
		}
		transferStatus = .mappingListeningPort

		if !mapper.open() {
			portMapperDidFinishWork(nil)
		}
	}

	func closePortMapping() {
		guard let portMapping else { return }

		portMapperNotifications.cancelAll()
		self.portMapping = nil
		portMapping.close()
	}

	func noteIPAddressLookupSucceeded() {
		guard transferStatus.isAwaitingAddress else { return }
		if isSender {
			transferStatus = isReversed ? .waitingForReceiverToAccept : .isListeningAsSender
		} else if isReversed {
			transferStatus = .isListeningAsReceiver
		} else {
			return
		}
		sendTransferRequestToClient()
		guard isSender, isReversed else { return }

		/* A reverse offer the peer never answers leaves a listening port open and
		 a row that says it is waiting, with nothing left to wait for. */
		let session = sessionID
		offerTimeout?.cancel()
		offerTimeout = Task { [weak self] in
			do { try await Task.sleep(for: FileTransferLimits.reverseOfferTimeout) } catch { return }
			guard let self, isCurrent(session), transferStatus == .waitingForReceiverToAccept else { return }
			close(with: .connectTimeout)
		}
	}

	func noteIPAddressLookupFailed() {
		guard transferStatus.isAwaitingAddress else { return }
		close(with: .sourceIPAddressUnknown)
	}

	/** `PortMapper` reports on every mDNSResponder callback, and a NAT-PMP
	 mapping is renewed for as long as it is held — so this fires again long
	 after the first result moved the transfer on. Only the first one has
	 anything to do. */
	private func portMapperDidFinishWork(_: Notification?) {
		guard transferStatus == .mappingListeningPort, let portMapping else { return }

		if portMapping.isMapped, portMapping.publicPort != 0 {
			/* The router picks the public port, and it need not be the one asked
			 for. The offer names it, and the peer's RESUME echoes it back, so it
			 is the port this transfer is known by from here on. */
			hostPort = portMapping.publicPort
			/* Bound to a local because the log message is an autoclosure, where
			 `self.` would be required and SwiftFormat would strip it. */
			let mappedPort = hostPort
			fileTransferLogger.info("Mapped DCC port \(mappedPort, privacy: .public)")
			updateIPAddress()
			return
		}

		fileTransferLogger.error(
			"DCC port mapping failed with code \(portMapping.error, privacy: .public)"
		)
		if isReversed {
			close(with: .noListeningPort)
		} else {
			updateIPAddress()
		}
	}

	/** Works out the address the offer names, and moves the transfer on.

	 The transfer waits for it in `waitingForLocalIPAddress`, which is what the
	 center settles when the address is known, known to be unavailable, or
	 looked up — whichever comes first. */
	private func updateIPAddress() {
		transferStatus = .waitingForLocalIPAddress
		switch transferCenter.resolveIPAddress(routerAddress: portMapping?.publicAddress) {
		case .known:
			noteIPAddressLookupSucceeded()
		case .unavailable:
			noteIPAddressLookupFailed()
		case .pending:
			break
		}
	}
}

// MARK: - The DCC negotiation this transfer answers

extension FileTransferController {
	func didReceiveResumeRequest(_ proposedPosition: UInt64) {
		guard isSender, proposedPosition > 0, totalFilesize >= proposedPosition,
		      [.waitingForReceiverToAccept, .isListeningAsSender].contains(transferStatus) else { return }
		let session = sessionID
		let transfer = transfer
		negotiationTask?.cancel()
		negotiationTask = Task { [weak self] in
			if let transfer, await transfer.commitResumeOffset(proposedPosition) == false {
				return
			}
			guard let self, isCurrent(session) else { return }
			isResume = true
			processedFilesize = proposedPosition
			sendTransferResumeAcceptToClient()
		}
	}

	func didReceiveResumeAccept(_ proposedPosition: UInt64) {
		/* An accept is only ever an answer to a resume this transfer asked for.
		 One that arrives at any other moment would move the offset into a file
		 nothing has claimed. */
		guard !isSender, transferStatus == .waitingForResumeAccept else { return }

		resumeRequestTimeout?.cancel()
		resumeRequestTimeout = nil

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
		let negotiation = negotiationTask
		let session = sessionID
		Task { [weak self] in
			await negotiation?.value
			guard let self, isCurrent(session), transferStatus == .connecting else { return }
			openConnectionToHost()
		}
	}

	func sendTransferRequestToClient() {
		guard let client else { return }

		if isSender {
			if isReversed {
				/* Offering a reverse DCC without a token is a malformed request
				 rather than a transfer the peer can complete. Report it. */
				guard buildTransferToken() else {
					fileTransferLogger.error("Could not mint a reverse DCC transfer token")
					close(with: .connectionUnavailable)
					return
				}

				client.sendFile(
					peerNickname,
					port: 0,
					filename: wireFilename,
					filesize: totalFilesize,
					token: transferToken
				)
			} else {
				client.sendFile(
					peerNickname,
					port: hostPort,
					filename: wireFilename,
					filesize: totalFilesize,
					token: nil
				)
			}
		} else if isReversed {
			client.sendFile(
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
		guard self.sessionID == sessionID, transferStatus == .waitingForResumeAccept else {
			return false
		}

		resumeRequestTimeout = nil
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
			if !transferCenter.fileTransferExists(withToken: candidate) {
				transferToken = candidate
				return true
			}
		}

		transferToken = nil
		return false
	}

	private func sendTransferResumeRequestToClient() {
		guard let ownedFile else { return }
		transferStatus = .initializing
		let session = sessionID
		let stopping = stopTask
		negotiationTask = Task { [weak self] in
			await stopping?.value
			do {
				let size = try await ownedFile.size()
				guard let self, isCurrent(session) else { return }
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
				guard let self, isCurrent(session) else { return }
				closeForRestart(with: .invalidResumePosition)
			}
		}
	}

	private func requestResume(position: UInt64) {
		resumeRequestTimeout?.cancel()
		let session = sessionID
		resumeRequestTimeout = Task { [weak self] in
			do {
				try await Task.sleep(for: .seconds(FileTransferLimits.resumeAcceptTimeout))
			} catch {
				return
			}

			guard Task.isCancelled == false, let self else { return }
			resumeTimeoutExpired(for: session)
		}
		transferStatus = .waitingForResumeAccept
		client?.sendFileResume(
			peerNickname,
			port: isReversed ? 0 : hostPort,
			filename: wireFilename,
			filesize: position,
			token: isReversed ? transferToken : nil
		)
	}

	private func sendTransferResumeAcceptToClient() {
		client?.sendFileResumeAccept(
			peerNickname,
			port: isReversed ? 0 : hostPort,
			filename: wireFilename,
			filesize: processedFilesize,
			token: isReversed ? transferToken : nil
		)
	}
}

// MARK: - Following the transfer actor

extension FileTransferController {
	/// Hands the transfer to a ``DCCTransfer`` actor and follows it.
	///
	/// Every event arrives back here on the main actor, which is where the
	/// status, the progress and the dialog all live, so nothing the actor
	/// reports has to cross isolation a second time.
	func startTransfer(with configuration: DCCTransfer.Configuration) {
		let transfer = DCCTransfer(configuration: configuration)
		self.transfer = transfer

		let stopping = stopTask

		transferEvents = Task { [weak self] in
			await stopping?.value
			guard Task.isCancelled == false else { await transfer.cancel(); return }
			await transfer.start()

			for await event in transfer.events {
				guard Task.isCancelled == false else { return }
				self?.transferDidReport(event, from: transfer)
			}
		}
	}

	/// Stops the running transfer, if there is one.
	func stopTransfer() {
		sessionID = UUID()
		transferEvents?.cancel()
		transferEvents = nil

		guard let transfer else {
			return
		}

		self.transfer = nil
		enqueueStop { await transfer.cancel() }
	}

	func transferDidReport(_ event: DCCTransferEvent, from transfer: DCCTransfer) {
		guard self.transfer === transfer else { return }
		switch event {
		case let .listening(port):
			listeningServerDidStart(on: port)
		case .connected:
			transferStatus = isSender ? .sending : .receiving
			transferCenter.updateMaintenanceTimer()
		case let .progress(processedBytes):
			transferDidProgress(to: processedBytes)
		case let .completion(completion):
			self.completion = completion
		case .finished:
			transferStatus = .complete
			close()
		case let .failed(error):
			transferDidFail(with: error)
		}
	}

	private func transferDidProgress(to processedBytes: UInt64) {
		/* `currentRecord` is the byte count the maintenance timer turns into a
		 transfer rate once a second, so it takes the delta, not the total. */
		if processedBytes > processedFilesize {
			currentRecord += processedBytes - processedFilesize
		}

		processedFilesize = processedBytes
	}

	private func transferDidFail(with error: DCCTransferError) {
		guard transferStatus.isFinished == false else {
			return
		}

		fileTransferLogger.error("DCC transfer failed: \(String(describing: error), privacy: .public)")
		close(with: FileTransferFailure(error))
	}
}
