/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\\__|\__,_|\__,_|_|
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

extension TDCFileTransferDialogTransferController {
	@objc public func open() {
		open(withPath: nil)
	}

	@objc public func openWithPathOrUserDownloads() {
		open(withPath: path == nil ? PathInfo.userDownloads : nil)
	}

	@objc(openWithPath:)
	public func open(withPath path: String?) {
		dispatchPrecondition(condition: .onQueue(.main))

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
		portMapperNotifications.observe(.XRPortMapperDidChanged, object: mapper) { [weak self] notification in
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

	@objc public func noteIPAddressLookupSucceeded() {
		if isSender {
			transferStatus = isReversed ? .waitingForReceiverToAccept : .isListeningAsSender
		} else if isReversed {
			transferStatus = .isListeningAsReceiver
		} else {
			return
		}
		sendTransferRequestToClient()
	}

	@objc public func noteIPAddressLookupFailed() {
		close(with: .sourceIPAddressUnknown)
	}

	@objc(didReceiveResumeRequest:)
	public func didReceiveResumeRequest(_ proposedPosition: UInt64) {
		dispatchPrecondition(condition: .onQueue(.main))
		guard proposedPosition > 0, currentFilesize >= proposedPosition else { return }

		isResume = true
		processedFilesize = proposedPosition
		sendTransferResumeAcceptToClient()
	}

	@objc(didReceiveResumeAccept:)
	public func didReceiveResumeAccept(_ proposedPosition: UInt64) {
		dispatchPrecondition(condition: .onQueue(.main))
		NSObject.cancelPreviousPerformRequests(
			withTarget: self,
			selector: #selector(transferResumeRequestTimeout),
			object: nil
		)

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

	@objc(didReceiveSendRequest:hostPort:)
	public func didReceiveSendRequest(_ hostAddress: String, hostPort: UInt16) {
		dispatchPrecondition(condition: .onQueue(.main))
		self.hostAddress = hostAddress
		self.hostPort = hostPort
		processedFilesize = 0
		openConnectionToHost()
	}

	@objc public func sendTransferRequestToClient() {
		guard let client else { return }

		if isSender {
			if isReversed {
				buildTransferToken()
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
		dispatchPrecondition(condition: .onQueue(.main))
		closeAndPostNotification(false)
		resetProperties()
		transferStatus = .connecting

		guard !hostAddress.isEmpty, hostPort != 0 else {
			fileTransferLogger.error("DCC connection has an invalid host address or port")
			close(with: .connectionUnavailable)
			return
		}

		let connection = TDCFileTransferDialogSocket(
			delegate: self,
			delegateQueue: DispatchQueue.main
		)
		connectionToRemoteServer = connection
		connection.connect(
			toHost: hostAddress,
			port: hostPort,
			viaInterface: TextualPreferences.fileTransferIPAddressInterfaceName(),
			timeout: FileTransferLimits.connectTimeout
		)
		disableSystemSleep()
	}

	private func openConnectionAsServer() {
		dispatchPrecondition(condition: .onQueue(.main))
		closeAndPostNotification(false)
		resetProperties()
		transferStatus = .initializing

		let portRangeStart = TextualPreferences.fileTransferPortRangeStart()
		let portRangeEnd = TextualPreferences.fileTransferPortRangeEnd()
		guard portRangeStart != 0, portRangeStart <= portRangeEnd else {
			close(with: .noListeningPort)
			return
		}

		let server = TDCFileTransferDialogSocket(
			delegate: self,
			delegateQueue: DispatchQueue.main
		)
		listeningServer = server
		server.listenOnPortRange(from: portRangeStart, to: portRangeEnd)
		disableSystemSleep()
	}

	@objc private func portMapperDidFinishWork(_: Notification?) {
		guard transferStatus == .mappingListeningPort, let portMapping else {
			assertionFailure("Port mapping completed in an invalid transfer state")
			return
		}

		if portMapping.isMapped {
			// swiftformat:disable:next redundantSelf
			fileTransferLogger.info("Mapped DCC port \(self.hostPort, privacy: .public)")
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
		var address = transferDialog.IPAddress
		let detectionMethod = TextualPreferences.fileTransferIPAddressDetectionMethod()
		let manuallyDetect = detectionMethod == .manual

		if address == nil, !manuallyDetect,
		   let publicAddress = portMapping?.publicAddress,
		   publicAddress.isIPAddress
		{
			transferDialog.IPAddress = publicAddress
			address = publicAddress
		}

		guard address != nil else {
			if manuallyDetect || detectionMethod == .routerOnly {
				noteIPAddressLookupFailed()
			} else {
				transferDialog.requestIPAddress()
				transferStatus = .waitingForLocalIPAddress
			}
			return
		}

		noteIPAddressLookupSucceeded()
	}

	private func buildTransferToken() {
		for _ in 0 ..< 300 {
			let candidate = String(randomNumber(9999))
			if !transferDialog.fileTransferExists(withToken: candidate) {
				transferToken = candidate
				return
			}
		}
	}

	private func sendTransferResumeRequestToClient() {
		dispatchPrecondition(condition: .onQueue(.main))
		guard currentFilesize > 0, currentFilesize <= totalFilesize else {
			transferResumeRequestTimeout()
			return
		}

		perform(
			#selector(transferResumeRequestTimeout),
			with: nil,
			afterDelay: FileTransferLimits.resumeAcceptTimeout,
			inModes: [.common]
		)
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

	@objc private func transferResumeRequestTimeout() {
		openTransfer()
	}

	private func resetProperties() {
		if !isResume {
			processedFilesize = 0
		}
		currentRecord = 0
		errorMessageDescription = nil
		sendQueueSize = 0
		speedRecordsPrivate.removeAll(keepingCapacity: true)
	}
}
