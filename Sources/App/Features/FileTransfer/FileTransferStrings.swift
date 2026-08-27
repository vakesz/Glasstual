/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \\ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\\___/_/\\_\\__|\\__,_|\\__,_|_|
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
	case sourceFileUnreadable
	case sourceIPAddressUnknown
	case storageFull
	case underlying(String)
}

enum FileTransferStrings {
	static var destinationPickerMessage: String {
		String(localized: .TDCFileTransferDialog.dcmW7)
	}

	static func failure(_ failure: FileTransferFailure, peerNickname: String) -> String {
		let resource = switch failure {
		case .connectionUnavailable:
			LocalizedStringResource.TDCFileTransferDialog.fn8Sx(peerNickname)
		case .fileHandlerFailed:
			LocalizedStringResource.TDCFileTransferDialog._05GC8(peerNickname)
		case .invalidResumePosition:
			LocalizedStringResource.TDCFileTransferDialog._0OvTr(peerNickname)
		case .noListeningPort:
			LocalizedStringResource.TDCFileTransferDialog.vxcSd(peerNickname)
		case .notConnectedToIRC:
			LocalizedStringResource.TDCFileTransferDialog._12P0V(peerNickname)
		case .sourceFileUnreadable:
			LocalizedStringResource.TDCFileTransferDialog.nabDx(peerNickname)
		case .sourceIPAddressUnknown:
			LocalizedStringResource.TDCFileTransferDialog._47S1S(peerNickname)
		case .storageFull:
			LocalizedStringResource.TDCFileTransferDialog._79FS0(peerNickname)
		case let .underlying(description):
			LocalizedStringResource.TDCFileTransferDialog.s793A(peerNickname, description)
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
			.TDCFileTransferDialog.jvhU7(peerNickname)
		case (.stopped, .outgoing):
			.TDCFileTransferDialog.w3HP8(peerNickname)
		case (.mappingListeningPort, .incoming):
			.TDCFileTransferDialog._49590(peerNickname)
		case (.mappingListeningPort, .outgoing):
			.TDCFileTransferDialog.j1Z88(peerNickname)
		case (.waitingForLocalIPAddress, .incoming):
			.TDCFileTransferDialog._6T1Mb(peerNickname)
		case (.waitingForLocalIPAddress, .outgoing):
			.TDCFileTransferDialog.onlAv(peerNickname)
		case (.initializing, .incoming):
			.TDCFileTransferDialog._42ZMg(peerNickname)
		case (.initializing, .outgoing):
			.TDCFileTransferDialog.pcvKg(peerNickname)
		case (.isListeningAsSender, _), (.waitingForReceiverToAccept, _):
			.TDCFileTransferDialog.ca52V(peerNickname)
		case (.isListeningAsReceiver, _):
			.TDCFileTransferDialog.pipZ6(peerNickname)
		case (.complete, .incoming):
			.TDCFileTransferDialog._6GuZa(peerNickname)
		case (.complete, .outgoing):
			.TDCFileTransferDialog.rx7Xy(peerNickname)
		case (.connecting, _):
			.TDCFileTransferDialog._7NfFr(peerNickname)
		case (.waitingForResumeAccept, _):
			.TDCFileTransferDialog.gxqZu(peerNickname)
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
			.TDCFileTransferDialog._9Xn7J(
				processedSize,
				totalSize,
				speed,
				peerNickname,
				timeRemaining
			)
		case (.incoming, nil):
			.TDCFileTransferDialog._7DkLp(processedSize, totalSize, speed, peerNickname)
		case let (.outgoing, timeRemaining?):
			.TDCFileTransferDialog.u17Ql(
				processedSize,
				totalSize,
				speed,
				peerNickname,
				timeRemaining
			)
		case (.outgoing, nil):
			.TDCFileTransferDialog.nvmNd(processedSize, totalSize, speed, peerNickname)
		}
		return String(localized: resource)
	}
}
