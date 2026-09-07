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

import AppKit
import CocoaExtensions
import Foundation
import os

enum FileTransferLimits {
	static let speedRecordCount = 10
	static let connectTimeout: TimeInterval = 30
	static let sendTimeout: TimeInterval = 30
	static let resumeAcceptTimeout: TimeInterval = 10
}

let fileTransferLogger = Logger(
	subsystem: Bundle.main.bundleIdentifier ?? "Glasstual",
	category: "FileTransfer"
)

public enum FileTransferStatus: UInt, Sendable {
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

/// Owns one DCC file transfer: what the user sees of it, and the negotiation
/// that surrounds it.
///
/// The bytes themselves belong to a ``DCCTransfer`` actor. The controller
/// starts one, follows its `AsyncStream` of events on the main actor, and
/// turns them into the status the dialog, IRCClient and the maintenance timer
/// read -- all of which are main-actor too.
@MainActor
public final class FileTransferController: ClientScoped {
	public internal(set) var client: IRCClient?
	public internal(set) var clientId: String?

	public internal(set) var isResume = false
	public internal(set) var isReversed = false
	public internal(set) var isSender = false
	public internal(set) var totalFilesize: UInt64 = 0
	public internal(set) var processedFilesize: UInt64 = 0
	public internal(set) var currentRecord: UInt64 = 0
	public internal(set) var errorMessageDescription: String?
	public internal(set) var path: String?
	public internal(set) var filename = ""
	var wireFilename = ""
	public internal(set) var hostAddress = ""
	public internal(set) var peerNickname = ""
	public internal(set) var transferToken: String?
	public internal(set) var uniqueIdentifier = UUID().uuidString
	public internal(set) var hostPort: UInt16 = 0

	public internal(set) var speedRecords: [UInt64] = []

	/// The descriptor this transfer reads from or writes into, and the
	/// authority for all byte I/O and resume validation.
	var ownedFile: DCCTransferFile? {
		didSet {
			/* The reservation is what settles which directory the user let us
			 reach, and the row still has to open and reveal the file once the
			 descriptor is closed. Keep the URL after the file goes, and never
			 replace a known one with nothing. */
			if let ownedFile {
				fileAccessURL = ownedFile.accessURL
			}
		}
	}

	/// An inactive capability URL, not an outstanding security-scope lease.
	var fileAccessURL: URL?
	var destinationAccessURL: URL?
	var negotiationTask: Task<Void, Never>?
	var stopTask: Task<Void, Never>?
	var sessionID = UUID()
	public internal(set) var completion: DCCTransfer.Completion?
	var portMapping: XRPortMapper?
	var transfer: DCCTransfer?
	var transferEvents: Task<Void, Never>?
	/// Gives up on an unanswered RESUME without truncating the partial file.
	var resumeRequestTimeout: Task<Void, Never>?
	var offerTimeout: Task<Void, Never>?
	var transferProgressHandler: NSObjectProtocol?
	var lifecycleNotifications = NotificationSubscriptions()
	var portMapperNotifications = NotificationSubscriptions()

	public internal(set) var transferStatus: FileTransferStatus = .stopped {
		didSet {
			if oldValue != transferStatus {
				reloadStatusInformation()
			}
		}
	}

	/// Whether starting this transfer would do anything: it is idle, and the
	/// reason it is idle is one a retry can get past. Every place that offers
	/// to start a transfer asks this, so they cannot drift apart.
	public var canStart: Bool {
		[.stopped, .recoverableError].contains(transferStatus)
	}

	private init(client: IRCClient) {
		self.client = client
		clientId = client.uniqueIdentifier
		prepareInitialState()
	}

	isolated deinit {
		negotiationTask?.cancel()
		resumeRequestTimeout?.cancel()
		offerTimeout?.cancel()
		transferEvents?.cancel()
		lifecycleNotifications.cancelAll()
		portMapperNotifications.cancelAll()
		portMapping?.close()
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

	public static func receiver(
		for client: IRCClient,
		nickname: String,
		address hostAddress: String,
		port hostPort: UInt16,
		filename: String,
		filesize totalFilesize: UInt64,
		token transferToken: String?
	) -> FileTransferController? {
		let wireFilename = filename.safeFilename
		guard !wireFilename.isEmpty, totalFilesize > 0 else { return nil }
		let controller = FileTransferController(client: client)

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

	public static func sender(
		for client: IRCClient,
		nickname: String,
		path: String,
		accessURL: URL? = nil
	) -> FileTransferController? {
		let filename = (path as NSString).lastPathComponent

		guard let file = try? DCCTransferFile(url: URL(fileURLWithPath: path), receiving: false, accessURL: accessURL)
		else {
			return nil
		}

		let totalFilesize = file.initialSize
		guard totalFilesize > 0 else {
			fileTransferLogger.error("Cannot create a sender for an empty file")
			return nil
		}

		let controller = FileTransferController(client: client)
		controller.isReversed = Preferences.FileTransfers.requestsAreReversed.value
		controller.isSender = true
		controller.peerNickname = nickname
		controller.path = (path as NSString).deletingLastPathComponent
		controller.filename = filename
		controller.wireFilename = filename.safeFilename
		controller.ownedFile = file
		controller.totalFilesize = totalFilesize
		return controller
	}

	private func prepareInitialState() {
		lifecycleNotifications.observe(.IRCClientDidDisconnect, object: client) { [weak self] notification in
			self?.clientDisconnected(notification)
		}
		lifecycleNotifications.observe(.IRCClientUserNicknameChanged, object: client) { [weak self] notification in
			self?.peerNicknameChanged(notification)
		}
	}
}
