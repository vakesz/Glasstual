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
		if self.path == nil {
			self.path = path
		}

		guard client?.isLoggedIn == true else {
			closeWithClientDisconnectedErrorImmediately()
			return
		}

		if isSender {
			openTransfer()
		} else {
			/* The resume offset is the size of the file this transfer writes
			 into, so the destination has to be settled before it is read. */
			claimDestinationFilename()
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
		if isSender {
			transferStatus = isReversed ? .waitingForReceiverToAccept : .isListeningAsSender
		} else if isReversed {
			transferStatus = .isListeningAsReceiver
		} else {
			return
		}
		sendTransferRequestToClient()
	}

	public func noteIPAddressLookupFailed() {
		close(with: .sourceIPAddressUnknown)
	}

	public func didReceiveResumeRequest(_ proposedPosition: UInt64) {
		guard proposedPosition > 0, currentFilesize >= proposedPosition else { return }

		isResume = true
		processedFilesize = proposedPosition
		sendTransferResumeAcceptToClient()
	}

	public func didReceiveResumeAccept(_ proposedPosition: UInt64) {
		/* An accept is only ever an answer to a resume this transfer asked for.
		 One that arrives at any other moment would move the offset into a file
		 nothing has claimed. */
		guard transferStatus == .waitingForResumeAccept else { return }

		resumeRequestTimeout?.cancel()
		resumeRequestTimeout = nil

		guard currentFilesize == proposedPosition else {
			close(
				with: .invalidResumePosition,
				isFatalError: true
			)
			return
		}

		isResume = true
		processedFilesize = currentFilesize
		openTransfer()
	}

	public func didReceiveSendRequest(_ hostAddress: String, hostPort: UInt16) {
		self.hostAddress = hostAddress
		self.hostPort = hostPort
		processedFilesize = 0
		openConnectionToHost()
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
					filename: filename,
					filesize: currentFilesize,
					token: transferToken
				)
			} else {
				client.sendFile(
					peerNickname,
					port: hostPort,
					filename: filename,
					filesize: currentFilesize,
					token: nil
				)
			}
		} else if isReversed {
			client.sendFile(
				peerNickname,
				port: hostPort,
				filename: filename,
				filesize: totalFilesize,
				token: transferToken
			)
		}
	}

	private func openTransfer() {
		switch (isSender, isReversed) {
		case (true, true):
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

		guard let filePath = prepareTransferFile() else { return }

		startTransfer(with: transferConfiguration(
			endpoint: .connect(
				host: hostAddress,
				port: hostPort,
				interfaceName: Preferences.FileTransfers.ipAddressInterfaceName.storedValue,
				timeout: .seconds(FileTransferLimits.connectTimeout)
			),
			filePath: filePath
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

		guard let filePath = prepareTransferFile() else { return }

		startTransfer(with: transferConfiguration(
			endpoint: .listen(portRange: portRangeStart ... portRangeEnd),
			filePath: filePath
		))
		disableSystemSleep()
	}

	private func transferConfiguration(
		endpoint: DCCTransfer.Endpoint,
		filePath: String
	) -> DCCTransfer.Configuration {
		DCCTransfer.Configuration(
			role: isSender ? .sender : .receiver,
			endpoint: endpoint,
			filePath: filePath,
			fileSize: totalFilesize,
			resumeOffset: processedFilesize,
			/* Only a reverse DCC names the peer up front. For a plain DCC SEND
				we listen and the peer announces itself by arriving, so there is
				nothing to check the inbound address against. */
			expectedPeerAddress: isActingAsServer ? hostAddress : "",
			sendTimeout: .seconds(FileTransferLimits.sendTimeout)
		)
	}

	/// The file this transfer reads from, or the one it writes into.
	private func prepareTransferFile() -> String? {
		if !isSender {
			claimDestinationFilename()
		}

		guard let filePath else {
			close(with: .sourceFileUnreadable)
			return nil
		}

		return filePath
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
				transferCenter.requestIPAddress()
				transferStatus = .waitingForLocalIPAddress
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
		/* `currentFilesize` is the claimed destination's size, so it is above
		 zero only when this transfer has already written part of the file. */
		guard currentFilesize > 0, currentFilesize <= totalFilesize else {
			openTransfer()
			return
		}

		resumeRequestTimeout?.cancel()
		resumeRequestTimeout = Task { [weak self] in
			do {
				try await Task.sleep(for: .seconds(FileTransferLimits.resumeAcceptTimeout))
			} catch {
				return
			}

			self?.resumeRequestTimeout = nil
			self?.openTransfer()
		}
		transferStatus = .waitingForResumeAccept
		client?.sendFileResume(
			peerNickname,
			port: isReversed ? 0 : hostPort,
			filename: filename,
			filesize: currentFilesize,
			token: isReversed ? transferToken : nil
		)
	}

	private func sendTransferResumeAcceptToClient() {
		client?.sendFileResumeAccept(
			peerNickname,
			port: isReversed ? 0 : hostPort,
			filename: filename,
			filesize: processedFilesize,
			token: isReversed ? transferToken : nil
		)
	}

	private func resetProperties() {
		if !isResume {
			processedFilesize = 0
		}
		currentRecord = 0
		errorMessageDescription = nil
		speedRecords.removeAll(keepingCapacity: true)
	}
}
