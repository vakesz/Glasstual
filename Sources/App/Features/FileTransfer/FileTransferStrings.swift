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
	case fileHandlerFailed
	case invalidResumePosition
	case noListeningPort
	case notConnectedToIRC
	case oversizedTransfer
	case sourceFileUnreadable
	case sourceIPAddressUnknown
	case storageFull
	case underlying(String)
}

extension FileTransferFailure {
	/// How a stopped transfer reads to the user.
	///
	/// The three descriptions spelled out here are the ones the transport has
	/// no localized string for; they replace the English `NSError` descriptions
	/// the socket used to carry.
	init(_ error: DCCTransferError) {
		switch error {
		case .badParameter, .rejectedPeerAddress:
			self = .connectionUnavailable
		case .closedByPeer:
			self = .underlying("Socket closed by remote peer")
		case .connectTimeout:
			self = .underlying("Connection attempt timed out")
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
			self = .underlying("Write operation timed out")
		}
	}
}

enum FileTransferStrings {
	static var fileTransfers: String {
		String(localized: .TDCFileTransferDialog.fileTransfers)
	}

	static var show: String {
		String(localized: .TDCFileTransferDialog.show)
	}

	static var all: String {
		String(localized: .TDCFileTransferDialog.all)
	}

	static var sending: String {
		String(localized: .TDCFileTransferDialog.sending)
	}

	static var receiving: String {
		String(localized: .TDCFileTransferDialog.receiving)
	}

	static var filterTransfers: String {
		String(localized: .TDCFileTransferDialog.filterTransfers)
	}

	static var noTransfers: String {
		String(localized: .TDCFileTransferDialog.noFileTransfers)
	}

	static var noTransfersDescription: String {
		String(localized: .TDCFileTransferDialog.transfersAppearHere)
	}

	static var clearStopped: String {
		String(localized: .TDCFileTransferDialog.clearAllStoppedTransfers)
	}

	static var startTransfer: String {
		String(localized: .TDCFileTransferDialog.startTransfer)
	}

	static var cancelTransfer: String {
		String(localized: .TDCFileTransferDialog.cancelTransfer)
	}

	static var quickLook: String {
		String(localized: .TDCFileTransferDialog.quickLook)
	}

	static var openFile: String {
		String(localized: .TDCFileTransferDialog.openFile)
	}

	static var showInFinder: String {
		String(localized: .TDCFileTransferDialog.showInFinder)
	}

	static var share: String {
		String(localized: .TDCFileTransferDialog.share)
	}

	static var removeFromList: String {
		String(localized: .TDCFileTransferDialog.removeFromList)
	}

	static var transferProgress: String {
		String(localized: .TDCFileTransferDialog.transferProgress)
	}

	static func transferCount(_ count: Int) -> String {
		String(localized: .TDCFileTransferDialog.transfers(count))
	}

	static var destinationPickerMessage: String {
		String(localized: .TDCFileTransferDialog.selectTheFolderInWhich)
	}

	static func failure(_ failure: FileTransferFailure, peerNickname: String) -> String {
		let resource = switch failure {
		case .connectionUnavailable:
			LocalizedStringResource.TDCFileTransferDialog.transferWithFailedCouldNotEstablish(peerNickname)
		case .fileHandlerFailed:
			LocalizedStringResource.TDCFileTransferDialog.transferWithFailedFileHandlerThrew(peerNickname)
		case .invalidResumePosition:
			LocalizedStringResource.TDCFileTransferDialog.transferWithFailedProposedResumePosition(peerNickname)
		case .noListeningPort:
			LocalizedStringResource.TDCFileTransferDialog.transferWithFailedThereIsNo(peerNickname)
		case .notConnectedToIRC:
			LocalizedStringResource.TDCFileTransferDialog.transferWithFailedYouAreNot(peerNickname)
		case .oversizedTransfer:
			LocalizedStringResource.TDCFileTransferDialog.transferFromFailedBecauseTheSender(peerNickname)
		case .sourceFileUnreadable:
			LocalizedStringResource.TDCFileTransferDialog.transferWithFailedCouldNotRead(peerNickname)
		case .sourceIPAddressUnknown:
			LocalizedStringResource.TDCFileTransferDialog.transferWithFailedUnknownSourceIp(peerNickname)
		case .storageFull:
			LocalizedStringResource.TDCFileTransferDialog.transferWithFailedNoSpaceLeft(peerNickname)
		case let .underlying(description):
			LocalizedStringResource.TDCFileTransferDialog.transferWithFailed(peerNickname, description)
		}
		return String(localized: resource)
	}

	static func status(
		_ status: FileTransferStatus,
		direction: FileTransferDirection,
		peerNickname: String
	) -> String? {
		let resource: LocalizedStringResource? = switch (status, direction) {
		case (.stopped, .incoming):
			.TDCFileTransferDialog.transferFromIsStoppedControlClick(peerNickname)
		case (.stopped, .outgoing):
			.TDCFileTransferDialog.transferToIsStoppedControlClick(peerNickname)
		case (.mappingListeningPort, .incoming):
			.TDCFileTransferDialog.transferFromAttemptingToMapListening(peerNickname)
		case (.mappingListeningPort, .outgoing):
			.TDCFileTransferDialog.transferToAttemptingToMapListening(peerNickname)
		case (.waitingForLocalIPAddress, .incoming):
			.TDCFileTransferDialog.transferFromDeterminingLocalIpAddress(peerNickname)
		case (.waitingForLocalIPAddress, .outgoing):
			.TDCFileTransferDialog.transferToDeterminingLocalIpAddress(peerNickname)
		case (.initializing, .incoming):
			.TDCFileTransferDialog.transferFromIsInitializing(peerNickname)
		case (.initializing, .outgoing):
			.TDCFileTransferDialog.transferToIsInitializing(peerNickname)
		case (.isListeningAsSender, _), (.waitingForReceiverToAccept, _):
			.TDCFileTransferDialog.transferToIsReadyWaiting(peerNickname)
		case (.isListeningAsReceiver, _):
			.TDCFileTransferDialog.transferFromIsReadyControlClick(peerNickname)
		case (.complete, .incoming):
			.TDCFileTransferDialog.transferFromIsCompleteControlClick(peerNickname)
		case (.complete, .outgoing):
			.TDCFileTransferDialog.transferToIsComplete(peerNickname)
		case (.connecting, _):
			.TDCFileTransferDialog.statusWhileConnecting(peerNickname)
		case (.waitingForResumeAccept, _):
			.TDCFileTransferDialog.transferFromWaitingForResponse(peerNickname)
		case (.fatalError, _), (.recoverableError, _), (.receiving, _), (.sending, _):
			nil
		@unknown default:
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
			.TDCFileTransferDialog.ofSReceivedFromRemaining(
				processedSize,
				totalSize,
				speed,
				peerNickname,
				timeRemaining
			)
		case (.incoming, nil):
			.TDCFileTransferDialog.ofSReceived(processedSize, totalSize, speed, peerNickname)
		case let (.outgoing, timeRemaining?):
			.TDCFileTransferDialog.ofSSentToRemaining(
				processedSize,
				totalSize,
				speed,
				peerNickname,
				timeRemaining
			)
		case (.outgoing, nil):
			.TDCFileTransferDialog.ofSSent(processedSize, totalSize, speed, peerNickname)
		}
		return String(localized: resource)
	}
}
