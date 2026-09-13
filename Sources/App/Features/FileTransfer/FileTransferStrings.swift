/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 *********************************************************************** */

import Foundation

enum FileTransferDirection: Sendable {
	case incoming
	case outgoing
}

enum FileTransferFailure: Equatable, Sendable {
	case connectionUnavailable
	case connectTimeout
	case fileHandlerFailed
	case invalidResumePosition
	case noListeningPort
	case notConnectedToIRC
	case oversizedTransfer
	case peerClosedConnection
	case sourceFileUnreadable
	case sourceIPAddressUnknown
	case storageFull
	case writeTimeout
	/// A transport error that arrived with its own description. Only
	/// ``DCCTransferError/network(_:)`` carries one; every other transport
	/// failure maps to a case above, which is what gives it localized copy.
	case underlying(String)
}

extension FileTransferFailure {
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
		case .writeTimeout:
			self = .writeTimeout
		}
	}
}

enum FileTransferStrings {
	static func unacknowledgedCompletion(peerNickname: String) -> String {
		String(localized: .FileTransfers.sentToWithoutAPeerAcknowledgement(peerNickname))
	}

	static var fileTransfers: String {
		String(localized: .FileTransfers.fileTransfers)
	}

	static var show: String {
		String(localized: .FileTransfers.show)
	}

	static var all: String {
		String(localized: .FileTransfers.all)
	}

	static var sending: String {
		String(localized: .FileTransfers.sending)
	}

	static var receiving: String {
		String(localized: .FileTransfers.receiving)
	}

	static var noTransfers: String {
		String(localized: .FileTransfers.noFileTransfers)
	}

	static var noTransfersDescription: String {
		String(localized: .FileTransfers.transfersAppearHere)
	}

	static var clearStopped: String {
		String(localized: .FileTransfers.clearAllStoppedTransfers)
	}

	static var startTransfer: String {
		String(localized: .FileTransfers.startTransfer)
	}

	static var acceptTransfer: String {
		String(localized: .FileTransfers.acceptTransfer)
	}

	static var retryTransfer: String {
		String(localized: .FileTransfers.retryTransfer)
	}

	static var cancelTransfer: String {
		String(localized: .FileTransfers.cancelTransfer)
	}

	static var quickLook: String {
		String(localized: .FileTransfers.quickLook)
	}

	static var openFile: String {
		String(localized: .FileTransfers.openFile)
	}

	static var showInFinder: String {
		String(localized: .FileTransfers.showInFinder)
	}

	static var share: String {
		String(localized: .FileTransfers.share)
	}

	static var removeFromList: String {
		String(localized: .FileTransfers.removeFromList)
	}

	static var transferProgress: String {
		String(localized: .FileTransfers.transferProgress)
	}

	/// The accessibility label for a row's size. The argument is already
	/// formatted as a byte count.
	static func totalSize(_ formattedSize: String) -> String {
		String(localized: .FileTransfers.transferTotalSize(formattedSize))
	}

	static func transferCount(_ count: Int) -> String {
		String(localized: .FileTransfers.transfers(count))
	}

	static func failure(_ failure: FileTransferFailure, peerNickname: String) -> String {
		let resource = switch failure {
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
		case .sourceFileUnreadable:
			LocalizedStringResource.FileTransfers.transferWithFailedCouldNotRead(peerNickname)
		case .sourceIPAddressUnknown:
			LocalizedStringResource.FileTransfers.transferWithFailedUnknownSourceIp(peerNickname)
		case .storageFull:
			LocalizedStringResource.FileTransfers.transferWithFailedNoSpaceLeft(peerNickname)
		case .writeTimeout:
			LocalizedStringResource.FileTransfers.transferWithFailedStalled(peerNickname)
		case let .underlying(description):
			LocalizedStringResource.FileTransfers.transferWithFailed(peerNickname, description)
		}
		return String(localized: resource)
	}

	/** How an idle or negotiating transfer reads in its row.

	 Every step between Start and the first byte — mapping a port, working out
	 this Mac's address, opening the socket — is one wait from the user's side,
	 and naming each of them separately told them nothing they could act on. */
	static func status(
		_ status: FileTransferStatus,
		direction: FileTransferDirection,
		peerNickname: String
	) -> String? {
		let resource: LocalizedStringResource? = switch (status, direction) {
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

	static func progress(
		direction: FileTransferDirection,
		processedSize: String,
		totalSize: String,
		speed: String,
		peerNickname: String,
		timeRemaining: String?
	) -> String {
		let resource: LocalizedStringResource = switch (direction, timeRemaining) {
		case let (.incoming, timeRemaining?):
			.FileTransfers.ofSReceivedFromRemaining(
				processedSize,
				totalSize,
				speed,
				peerNickname,
				timeRemaining
			)
		case (.incoming, nil):
			.FileTransfers.ofSReceived(processedSize, totalSize, speed, peerNickname)
		case let (.outgoing, timeRemaining?):
			.FileTransfers.ofSSentToRemaining(
				processedSize,
				totalSize,
				speed,
				peerNickname,
				timeRemaining
			)
		case (.outgoing, nil):
			.FileTransfers.ofSSent(processedSize, totalSize, speed, peerNickname)
		}
		return String(localized: resource)
	}
}
