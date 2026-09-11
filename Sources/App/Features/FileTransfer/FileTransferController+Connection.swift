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

extension FileTransferController {
	public func open() {
		open(withPath: nil)
	}

	public func openWithPathOrUserDownloads() {
		open(withPath: path == nil ? PathInfo.userDownloads : nil)
	}

	public func open(withPath path: String?) {
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
			/* The resume offset is the size of the file this transfer writes
			 into, so the destination has to be settled before it is read. */
			claimDestinationFilename()
			guard ownedFile != nil else { return }
			sendTransferResumeRequestToClient()
		}
	}

	func listeningServerDidStart(on port: UInt16) {
		guard transferStatus == .initializing else {
			assertionFailure("Listener started in an invalid transfer state")
			return
		}

		hostPort = port
		let mapper = XRPortMapper(port: port)
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

	public func noteIPAddressLookupSucceeded() {
		guard [.initializing, .mappingListeningPort, .waitingForLocalIPAddress].contains(transferStatus) else { return }
		if isSender {
			transferStatus = isReversed ? .waitingForReceiverToAccept : .isListeningAsSender
		} else if isReversed {
			transferStatus = .isListeningAsReceiver
		} else {
			return
		}
		sendTransferRequestToClient()
		if isSender, isReversed {
			let sessionID = sessionID
			offerTimeout?.cancel()
			offerTimeout = Task { [weak self] in
				do { try await Task.sleep(for: .seconds(120)) } catch { return }
				guard let self, self.sessionID == sessionID,
				      transferStatus == .waitingForReceiverToAccept else { return }
				close(with: FileTransferFailure(.connectTimeout))
			}
		}
	}

	public func noteIPAddressLookupFailed() {
		guard [.initializing, .mappingListeningPort, .waitingForLocalIPAddress].contains(transferStatus) else { return }
		close(with: .sourceIPAddressUnknown)
	}

	public func didReceiveResumeRequest(_ proposedPosition: UInt64) {
		guard isSender, proposedPosition > 0, totalFilesize >= proposedPosition,
		      [.waitingForReceiverToAccept, .isListeningAsSender].contains(transferStatus) else { return }
		let sessionID = sessionID
		let transfer = transfer
		negotiationTask?.cancel()
		negotiationTask = Task { [weak self] in
			if let transfer, await transfer.commitResumeOffset(proposedPosition) == false {
				return
			}
			guard !Task.isCancelled, let self, self.sessionID == sessionID else { return }
			isResume = true
			processedFilesize = proposedPosition
			sendTransferResumeAcceptToClient()
		}
	}

	public func didReceiveResumeAccept(_ proposedPosition: UInt64) {
		/* An accept is only ever an answer to a resume this transfer asked for.
		 One that arrives at any other moment would move the offset into a file
		 nothing has claimed. */
		guard !isSender, transferStatus == .waitingForResumeAccept else { return }

		resumeRequestTimeout?.cancel()
		resumeRequestTimeout = nil

		guard proposedPosition > 0, proposedPosition <= totalFilesize, processedFilesize == proposedPosition else {
			close(
				with: .invalidResumePosition,
				isFatalError: true
			)
			return
		}

		isResume = true
		openTransfer()
	}

	public func didReceiveSendRequest(_ hostAddress: String, hostPort: UInt16) {
		guard isSender, isReversed, transferStatus == .waitingForReceiverToAccept else { return }
		self.hostAddress = hostAddress
		self.hostPort = hostPort
		transferStatus = .connecting
		let negotiation = negotiationTask
		let sessionID = sessionID
		Task { [weak self] in
			await negotiation?.value
			guard let self, self.sessionID == sessionID, transferStatus == .connecting else { return }
			openConnectionToHost()
		}
	}

	public func sendTransferRequestToClient() {
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

	private func openTransfer() {
		switch (isSender, isReversed) {
		case (true, true):
			closeAndPostNotification(false)
			resetProperties()
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
		resetProperties()
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
		resetProperties()
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
		if !isSender {
			claimDestinationFilename()
		}

		guard let ownedFile else {
			close(with: .sourceFileUnreadable)
			return nil
		}

		return ownedFile
	}

	/** `XRPortMapper` reports on every mDNSResponder callback, and a NAT-PMP
	 mapping is renewed for as long as it is held — so this fires again long
	 after the first result moved the transfer on. Only the first one has
	 anything to do. */
	private func portMapperDidFinishWork(_: Notification?) {
		guard transferStatus == .mappingListeningPort, let portMapping else { return }

		if portMapping.isMapped {
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

	private func updateIPAddress() {
		var address = transferCenter.IPAddress
		let detectionMethod = Preferences.FileTransfers.ipAddressDetectionMethod.value
		let manuallyDetect = detectionMethod == .manual

		if address == nil, !manuallyDetect,
		   let publicAddress = portMapping?.publicAddress,
		   publicAddress.isIPAddress
		{
			transferCenter.IPAddress = publicAddress
			address = publicAddress
		}

		guard address != nil else {
			if manuallyDetect || detectionMethod == .routerOnly {
				noteIPAddressLookupFailed()
			} else {
				transferStatus = .waitingForLocalIPAddress
				transferCenter.requestIPAddress()
			}
			return
		}

		noteIPAddressLookupSucceeded()
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
		let sessionID = sessionID
		let stopping = stopTask
		negotiationTask = Task { [weak self] in
			await stopping?.value
			do {
				let size = try await ownedFile.size()
				guard !Task.isCancelled, let self, self.sessionID == sessionID else { return }
				guard size <= totalFilesize else { close(with: .invalidResumePosition, isFatalError: true); return }
				processedFilesize = size
				isResume = false
				if size == 0 {
					openTransfer(); return
				}
				requestResume(position: size)
			} catch {
				guard !Task.isCancelled, let self, self.sessionID == sessionID else { return }
				close(with: .invalidResumePosition, isFatalError: true)
			}
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
		close(with: .invalidResumePosition)

		return true
	}

	private func requestResume(position: UInt64) {
		resumeRequestTimeout?.cancel()
		let sessionID = sessionID
		resumeRequestTimeout = Task { [weak self] in
			do {
				try await Task.sleep(for: .seconds(FileTransferLimits.resumeAcceptTimeout))
			} catch {
				return
			}

			guard !Task.isCancelled, let self else { return }
			resumeTimeoutExpired(for: sessionID)
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

	private func resetProperties() {
		completion = nil
		if !isResume {
			processedFilesize = 0
		}
		currentRecord = 0
		errorMessageDescription = nil
		speedRecords.removeAll(keepingCapacity: true)
	}
}
