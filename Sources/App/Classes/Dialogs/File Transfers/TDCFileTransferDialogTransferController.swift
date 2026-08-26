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

import AppKit
import Darwin
import Foundation
import os

private enum FileTransferLimits {
	static let speedRecordCount = 10
	static let maximumSendQueueSize = 2
	static let bufferSize = 64 * 1024
	static let rateLimit: UInt64 = 10 * 1024 * 1024
	static let connectTimeout: TimeInterval = 30
	static let sendTimeout: TimeInterval = 30
	static let resumeAcceptTimeout: TimeInterval = 10
}

private let fileTransferLogger = Logger(
	subsystem: Bundle.main.bundleIdentifier ?? "Glasstual",
	category: "FileTransfer"
)

/// Owns one DCC file transfer.
///
/// The controller and its mutable state are confined to the main queue. The
/// Network.framework socket wrapper delivers delegate callbacks on that queue,
/// and IRCClient, the dialog, the maintenance timer, and AppKit all call from it.
@objc(TDCFileTransferDialogTransferController)
@MainActor
public final class TDCFileTransferDialogTransferController: NSObject,
	TDCClientPrototype,
	TDCFileTransferDialogSocketDelegate
{
	@objc public private(set) var client: IRCClient?
	@objc public private(set) var clientId: String?
	@objc public weak var transferTableCell: FileTransferDialogTableCell?

	@objc public private(set) var isResume = false
	@objc public private(set) var isReversed = false
	@objc public private(set) var isSender = false
	@objc public private(set) var totalFilesize: UInt64 = 0
	@objc public private(set) var processedFilesize: UInt64 = 0
	@objc public private(set) var currentRecord: UInt64 = 0
	@objc public private(set) var errorMessageDescription: String?
	@objc public private(set) var path: String?
	@objc public private(set) var filename = ""
	@objc public private(set) var hostAddress = ""
	@objc public private(set) var peerNickname = ""
	@objc public private(set) var transferToken: String?
	@objc public private(set) var uniqueIdentifier = UUID().uuidString
	@objc public private(set) var hostPort: UInt16 = 0

	private var speedRecordsPrivate: [NSNumber] = []
	private var fileHandle: FileHandle?
	private var portMapping: XRPortMapper?
	private var sendQueueSize = 0
	private var listeningServer: TDCFileTransferDialogSocket?
	private var listeningServerConnectedClient: TDCFileTransferDialogSocket?
	private var connectionToRemoteServer: TDCFileTransferDialogSocket?
	private var transferProgressHandler: NSObjectProtocol?

	@objc public private(set) var transferStatus: TDCFileTransferDialogTransferStatus = .stopped {
		didSet {
			dispatchPrecondition(condition: .onQueue(.main))
			if oldValue != transferStatus {
				reloadStatusInformation()
			}
		}
	}

	@available(*, unavailable)
	override public init() {
		fatalError("Use receiver(for:...) or sender(for:...)")
	}

	private init(client: IRCClient) {
		self.client = client
		clientId = client.uniqueIdentifier
		super.init()
		prepareInitialState()
	}

	deinit {
		NotificationCenter.default.removeObserver(self)
	}

	// MARK: - Construction and lifetime

	@objc(receiverForClient:nickname:address:port:filename:filesize:token:)
	public class func receiver(
		for client: IRCClient,
		nickname: String,
		address hostAddress: String,
		port hostPort: UInt16,
		filename: String,
		filesize totalFilesize: UInt64,
		token transferToken: String?
	) -> TDCFileTransferDialogTransferController? {
		let controller = TDCFileTransferDialogTransferController(client: client)

		if let transferToken, transferToken.isEmpty == false {
			controller.transferToken = transferToken
			controller.isReversed = true
		}

		controller.peerNickname = nickname
		controller.hostAddress = hostAddress
		controller.hostPort = hostPort
		controller.filename = filename
		controller.totalFilesize = totalFilesize
		return controller
	}

	@objc(senderForClient:nickname:path:)
	public class func sender(
		for client: IRCClient,
		nickname: String,
		path: String
	) -> TDCFileTransferDialogTransferController? {
		let filename = (path as NSString).lastPathComponent

		guard let attributes = try? FileManager.default.attributesOfItem(atPath: path),
		      let fileSize = attributes[.size] as? NSNumber
		else {
			return nil
		}

		let totalFilesize = fileSize.uint64Value
		guard totalFilesize > 0 else {
			fileTransferLogger.error("Cannot create a sender for an empty file")
			return nil
		}

		let controller = TDCFileTransferDialogTransferController(client: client)
		controller.isReversed = TPCPreferences.fileTransferRequestsAreReversed()
		controller.isSender = true
		controller.peerNickname = nickname
		controller.path = (path as NSString).deletingLastPathComponent
		controller.filename = filename
		controller.totalFilesize = totalFilesize
		return controller
	}

	private func prepareInitialState() {
		dispatchPrecondition(condition: .onQueue(.main))
		NotificationCenter.default.addObserver(
			self,
			selector: #selector(clientDisconnected(_:)),
			name: .IRCClientDidDisconnect,
			object: client
		)
		NotificationCenter.default.addObserver(
			self,
			selector: #selector(peerNicknameChanged(_:)),
			name: .IRCClientUserNicknameChanged,
			object: client
		)
	}

	@objc public func prepareForPermanentDestruction() {
		dispatchPrecondition(condition: .onQueue(.main))
		transferTableCell = nil
		closeAndPostNotification(false)
		NotificationCenter.default.removeObserver(self)
	}

	// MARK: - Errors

	private func failWithNoSpaceLeftOnDevice() {
		close(withLocalizedError: "TDCFileTransferDialog[79f-s0]")
	}

	private func close(
		withLocalizedError localizationKey: String,
		description: String? = nil,
		isFatalError: Bool = false
	) {
		if let description {
			errorMessageDescription = LocalizedKey(localizationKey, peerNickname, description)
		} else {
			errorMessageDescription = LocalizedKey(localizationKey, peerNickname)
		}

		transferStatus = isFatalError ? .fatalError : .recoverableError
		close()
	}

	// MARK: - Opening and closing

	private func disableSystemSleep() {
		transferProgressHandler =
			ProcessInfo.processInfo.beginActivity(
				options: .userInitiated,
				reason: "Transferring file"
			) as NSObjectProtocol
	}

	private func enableSystemSleep() {
		guard let transferProgressHandler else {
			return
		}

		ProcessInfo.processInfo.endActivity(transferProgressHandler)
		self.transferProgressHandler = nil
	}

	@objc public func open() {
		open(withPath: nil)
	}

	@objc public func openWithPathOrUserDownloads() {
		open(withPath: path == nil ? TPCPathInfo.userDownloads : nil)
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

		guard hostAddress.isEmpty == false, hostPort != 0 else {
			fileTransferLogger.error("DCC connection has an invalid host address or port")
			close(withLocalizedError: "TDCFileTransferDialog[fn8-sx]")
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
			viaInterface: TPCPreferences.fileTransferIPAddressInterfaceName(),
			timeout: FileTransferLimits.connectTimeout
		)
		disableSystemSleep()
	}

	private func openConnectionAsServer() {
		dispatchPrecondition(condition: .onQueue(.main))
		closeAndPostNotification(false)
		resetProperties()
		transferStatus = .initializing

		let portRangeStart = TPCPreferences.fileTransferPortRangeStart()
		let portRangeEnd = TPCPreferences.fileTransferPortRangeEnd()
		guard portRangeStart != 0, portRangeStart <= portRangeEnd else {
			close(withLocalizedError: "TDCFileTransferDialog[vxc-sd]")
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

	private func listeningServerDidStart(on port: UInt16) {
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

		NotificationCenter.default.addObserver(
			self,
			selector: #selector(portMapperDidFinishWork(_:)),
			name: .XRPortMapperDidChanged,
			object: mapper
		)
		transferStatus = .mappingListeningPort

		if mapper.open() == false {
			portMapperDidFinishWork(nil)
		}
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
			close(withLocalizedError: "TDCFileTransferDialog[vxc-sd]")
		} else {
			updateIPAddress()
		}
	}

	private func updateIPAddress() {
		var address = transferDialog.IPAddress
		let detectionMethod = TPCPreferences.fileTransferIPAddressDetectionMethod()
		let manuallyDetect = detectionMethod == .manual

		if address == nil, manuallyDetect == false,
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

	private func closePortMapping() {
		guard let portMapping else {
			return
		}

		NotificationCenter.default.removeObserver(
			self,
			name: .XRPortMapperDidChanged,
			object: portMapping
		)
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
		close(withLocalizedError: "TDCFileTransferDialog[47s-1s]")
	}

	// MARK: - DCC negotiation

	@objc(didReceiveResumeRequest:)
	public func didReceiveResumeRequest(_ proposedPosition: UInt64) {
		dispatchPrecondition(condition: .onQueue(.main))
		guard proposedPosition > 0, currentFilesize >= proposedPosition else {
			return
		}

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
				withLocalizedError: "TDCFileTransferDialog[0ov-tr]",
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

	private func buildTransferToken() {
		for _ in 0 ..< 300 {
			let candidate = String(randomNumber(9999))
			if transferDialog.fileTransferExists(withToken: candidate) == false {
				transferToken = candidate
				return
			}
		}
	}

	@objc public func sendTransferRequestToClient() {
		guard let client else {
			return
		}

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

	@objc private func peerNicknameChanged(_ notification: Notification) {
		guard let oldNickname = notification.userInfo?["oldNickname"] as? String,
		      peerNickname == oldNickname,
		      let newNickname = notification.userInfo?["newNickname"] as? String
		else {
			return
		}
		peerNickname = newNickname
	}

	@objc private func clientDisconnected(_: Notification) {
		closeWithClientDisconnectedError()
	}

	private func closeWithClientDisconnectedError() {
		let pendingStatuses: Set<TDCFileTransferDialogTransferStatus> = [
			.connecting,
			.initializing,
			.isListeningAsReceiver,
			.isListeningAsSender,
			.mappingListeningPort,
			.waitingForLocalIPAddress,
			.waitingForReceiverToAccept,
			.waitingForResumeAccept,
		]
		guard pendingStatuses.contains(transferStatus) else {
			return
		}
		closeWithClientDisconnectedErrorImmediately()
	}

	private func closeWithClientDisconnectedErrorImmediately() {
		close(withLocalizedError: "TDCFileTransferDialog[12p-0v]")
	}

	@objc public func close() {
		closeAndPostNotification(true)
	}

	@objc(closeAndPostNotification:)
	public func closeAndPostNotification(_ postNotification: Bool) {
		dispatchPrecondition(condition: .onQueue(.main))
		NSObject.cancelPreviousPerformRequests(withTarget: self)

		listeningServer?.disconnect()
		listeningServer = nil
		listeningServerConnectedClient?.disconnect()
		listeningServerConnectedClient = nil
		connectionToRemoteServer?.disconnect()
		connectionToRemoteServer = nil
		closePortMapping()
		closeFileHandle()

		if [.complete, .fatalError, .recoverableError].contains(transferStatus) == false {
			transferStatus = .stopped
		}

		if postNotification {
			postCompletionNotificationIfNeeded()
		}

		transferDialog.updateMaintenanceTimer()
		enableSystemSleep()
	}

	private func postCompletionNotificationIfNeeded() {
		guard let client else {
			return
		}

		let type: TXNotificationType
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

	// MARK: - Maintenance and files

	@objc public func onMaintenanceTimer() {
		dispatchPrecondition(condition: .onQueue(.main))
		guard transferStatus == .receiving || transferStatus == .sending else {
			assertionFailure("Maintenance timer fired for an inactive transfer")
			return
		}

		speedRecordsPrivate.append(NSNumber(value: currentRecord))
		if speedRecordsPrivate.count > FileTransferLimits.speedRecordCount {
			speedRecordsPrivate.removeFirst()
		}
		currentRecord = 0
		reloadStatusInformation()
		send()
	}

	private func setNonexistentFilename() {
		guard var candidatePath = filePath,
		      FileManager.default.fileExists(atPath: candidatePath)
		else {
			return
		}

		let filenameExtension = (filename as NSString).pathExtension
		let stem = (filename as NSString).deletingPathExtension
		var suffix = 1
		repeat {
			let candidateName =
				filenameExtension.isEmpty
					? "\(stem)_\(suffix)"
					: "\(stem)_\(suffix).\(filenameExtension)"
			candidatePath = (path! as NSString).appendingPathComponent(candidateName)
			suffix += 1
		} while FileManager.default.fileExists(atPath: candidatePath)

		filename = (candidatePath as NSString).lastPathComponent
	}

	private func openFileHandle() -> Bool {
		guard var filePath else {
			close(withLocalizedError: "TDCFileTransferDialog[nab-dx]")
			return false
		}

		if isSender == false, isResume == false {
			setNonexistentFilename()
			guard let updatedPath = self.filePath else {
				close(withLocalizedError: "TDCFileTransferDialog[nab-dx]")
				return false
			}
			filePath = updatedPath
			FileManager.default.createFile(atPath: filePath, contents: Data())
		}

		guard let handle = FileHandle(forUpdatingAtPath: filePath) else {
			close(withLocalizedError: "TDCFileTransferDialog[nab-dx]")
			return false
		}

		if isResume {
			do {
				try handle.seek(toOffset: processedFilesize)
			} catch {
				fileTransferLogger.error(
					"Failed to seek transfer file: \(error.localizedDescription, privacy: .public)"
				)
				try? handle.close()
				close(withLocalizedError: "TDCFileTransferDialog[nab-dx]")
				return false
			}
		}

		fileHandle = handle
		return true
	}

	private func closeFileHandle() {
		guard let fileHandle else {
			return
		}

		do {
			try fileHandle.close()
		} catch {
			fileTransferLogger.error(
				"Failed to close transfer file: \(error.localizedDescription, privacy: .public)"
			)
		}
		self.fileHandle = nil
	}

	// MARK: - Socket delegate

	public func socket(_ socket: TDCFileTransferDialogSocket, didStartListeningOnPort port: UInt16) {
		dispatchPrecondition(condition: .onQueue(.main))
		guard socket === listeningServer else {
			return
		}
		listeningServerDidStart(on: port)
	}

	public func socket(_ socket: TDCFileTransferDialogSocket, didFailToListenWithError error: Error) {
		dispatchPrecondition(condition: .onQueue(.main))
		guard socket === listeningServer else {
			return
		}
		fileTransferLogger.error("DCC listener failed: \(error.localizedDescription, privacy: .public)")
		close(withLocalizedError: "TDCFileTransferDialog[vxc-sd]")
	}

	public func socket(
		_ socket: TDCFileTransferDialogSocket,
		didAcceptConnection connection: TDCFileTransferDialogSocket
	) {
		dispatchPrecondition(condition: .onQueue(.main))
		guard socket === listeningServer, isActingAsServer else {
			connection.disconnect()
			return
		}
		guard listeningServerConnectedClient == nil else {
			connection.disconnect()
			return
		}

		listeningServerConnectedClient = connection
		transferStatus = isReversed ? .receiving : .sending
		transferDialog.updateMaintenanceTimer()
		guard openFileHandle() else {
			return
		}

		if isReversed {
			readSocket?.readData()
		} else {
			send()
		}
	}

	public func socketDidConnect(_ socket: TDCFileTransferDialogSocket) {
		dispatchPrecondition(condition: .onQueue(.main))
		guard socket === connectionToRemoteServer, isActingAsClient else {
			return
		}

		transferStatus = isReversed ? .sending : .receiving
		transferDialog.updateMaintenanceTimer()
		guard openFileHandle() else {
			return
		}

		if isReversed {
			send()
		} else {
			readSocket?.readData()
		}
	}

	public func socket(_ socket: TDCFileTransferDialogSocket, didDisconnectWithError error: Error?) {
		dispatchPrecondition(condition: .onQueue(.main))
		guard
			socket === listeningServer
			|| socket === listeningServerConnectedClient
			|| socket === connectionToRemoteServer
		else {
			return
		}
		guard [.complete, .fatalError, .recoverableError].contains(transferStatus) == false else {
			return
		}

		if let error {
			close(
				withLocalizedError: "TDCFileTransferDialog[s79-3a]",
				description: error.localizedDescription
			)
		} else {
			close()
		}
	}

	public func socket(_ socket: TDCFileTransferDialogSocket, didRead data: Data) {
		dispatchPrecondition(condition: .onQueue(.main))
		guard socket === readSocket, isSender == false, let fileHandle else {
			return
		}

		currentRecord += UInt64(data.count)
		processedFilesize += UInt64(data.count)

		if data.isEmpty == false {
			do {
				try fileHandle.write(contentsOf: data)
			} catch {
				fileTransferLogger.error(
					"Failed to write transfer data: \(error.localizedDescription, privacy: .public)"
				)
				let cocoaError = error as NSError
				if cocoaError.domain == NSPOSIXErrorDomain, cocoaError.code == ENOSPC {
					failWithNoSpaceLeftOnDevice()
				} else {
					close(withLocalizedError: "TDCFileTransferDialog[05g-c8]")
				}
				return
			}
		}

		let acknowledgedBytes = UInt32(truncatingIfNeeded: processedFilesize)
		let acknowledgement = Data([
			UInt8(truncatingIfNeeded: acknowledgedBytes >> 24),
			UInt8(truncatingIfNeeded: acknowledgedBytes >> 16),
			UInt8(truncatingIfNeeded: acknowledgedBytes >> 8),
			UInt8(truncatingIfNeeded: acknowledgedBytes),
		])
		readSocket?.write(acknowledgement, timeout: -1)

		if processedFilesize < totalFilesize {
			readSocket?.readData()
			return
		}

		transferStatus = .complete
		close()
	}

	public func socketDidWriteData(_ socket: TDCFileTransferDialogSocket) {
		dispatchPrecondition(condition: .onQueue(.main))
		guard socket === writeSocket, isSender else {
			return
		}

		if sendQueueSize > 0 {
			sendQueueSize -= 1
		}
		if processedFilesize < totalFilesize {
			send()
			return
		}
		guard sendQueueSize == 0 else {
			return
		}

		transferStatus = .complete
		close()
	}

	private func send() {
		guard isSender, transferStatus == .sending, let fileHandle, let writeSocket else {
			return
		}

		while currentRecord < FileTransferLimits.rateLimit,
		      sendQueueSize < FileTransferLimits.maximumSendQueueSize,
		      processedFilesize < totalFilesize
		{
			let data: Data
			do {
				guard let result = try fileHandle.read(upToCount: FileTransferLimits.bufferSize),
				      result.isEmpty == false
				else {
					close(withLocalizedError: "TDCFileTransferDialog[nab-dx]")
					return
				}
				data = result
			} catch {
				fileTransferLogger.error(
					"Failed to read transfer data: \(error.localizedDescription, privacy: .public)"
				)
				close(withLocalizedError: "TDCFileTransferDialog[nab-dx]")
				return
			}

			currentRecord += UInt64(data.count)
			processedFilesize += UInt64(data.count)
			sendQueueSize += 1
			writeSocket.write(data, timeout: FileTransferLimits.sendTimeout)
		}
	}

	// MARK: - Dialog integration and derived properties

	@objc public func updateClearButton() {
		transferDialog.updateClearButton()
	}

	@objc public func reloadStatusInformation() {
		transferTableCell?.reloadStatusInformation()
	}

	private var writeSocket: TDCFileTransferDialogSocket? {
		isReversed ? connectionToRemoteServer : listeningServerConnectedClient
	}

	private var readSocket: TDCFileTransferDialogSocket? {
		isReversed ? listeningServerConnectedClient : connectionToRemoteServer
	}

	@objc public var isActingAsServer: Bool {
		isSender != isReversed
	}

	@objc public var isActingAsClient: Bool {
		isSender == isReversed
	}

	private var transferDialog: TDCFileTransferDialog {
		TXSharedApplication.sharedFileTransferDialog()
	}

	@objc public var speedRecords: [NSNumber] {
		dispatchPrecondition(condition: .onQueue(.main))
		return speedRecordsPrivate
	}

	@objc public var filePath: String? {
		guard let path else {
			return nil
		}
		return (path as NSString).appendingPathComponent(filename)
	}

	@objc public var fileURL: URL? {
		filePath.map { URL(fileURLWithPath: $0) }
	}

	private var currentFilesize: UInt64 {
		guard let filePath,
		      let attributes = try? FileManager.default.attributesOfItem(atPath: filePath),
		      let fileSize = attributes[.size] as? NSNumber
		else {
			return 0
		}
		return fileSize.uint64Value
	}

	private func resetProperties() {
		if isResume == false {
			processedFilesize = 0
		}
		currentRecord = 0
		errorMessageDescription = nil
		sendQueueSize = 0
		speedRecordsPrivate.removeAll(keepingCapacity: true)
	}
}
