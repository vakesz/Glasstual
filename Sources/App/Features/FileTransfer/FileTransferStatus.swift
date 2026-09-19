// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2018 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/*  The vocabulary a transfer's state is read in: which phase it is in, which
 way it runs, and why it stopped — each with the wording a row says it in.

 All three are asked about from everywhere in the feature: the row, the list,
 the receiver limit, the address lookup and the negotiation. They are values
 with no transfer of their own, which is what lets one answer be shared rather
 than spelled out again at each place that asks. */

enum FileTransferStatus: UInt, Sendable {
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

/** What each status means to the rest of the feature.

 The same handful of status groups used to be spelled out as a set literal at
 every place that asked — the receiver limit, the row list, the close path, the
 address lookup — and a new status had to be remembered in all of them. */
extension FileTransferStatus {
	/// Bytes are moving right now.
	var isActive: Bool {
		self == .sending || self == .receiving
	}

	/// The two ends are still agreeing how to reach each other. No byte of the
	/// file has crossed yet, but the transfer is under way.
	var isNegotiating: Bool {
		switch self {
		case .connecting, .initializing, .isListeningAsReceiver, .isListeningAsSender,
		     .mappingListeningPort, .waitingForLocalIPAddress, .waitingForReceiverToAccept,
		     .waitingForResumeAccept:
			true
		case .complete, .fatalError, .receiving, .recoverableError, .sending, .stopped:
			false
		}
	}

	/// Whether the transfer is spending resources: a slot against the receiver
	/// limit, room on the destination volume, a tick of the maintenance timer.
	var isRunning: Bool {
		isActive || isNegotiating
	}

	/// The transfer reached an answer. `stopped` is not one: it is a transfer
	/// that has not been started.
	var isFinished: Bool {
		self == .complete || self == .fatalError || self == .recoverableError
	}

	/// The phase an address lookup is allowed to move the transfer on from.
	var isAwaitingAddress: Bool {
		self == .initializing || self == .mappingListeningPort || self == .waitingForLocalIPAddress
	}

	/// The transfer is idle, and the reason it is idle is one a retry can get
	/// past. Every place that offers to start a transfer asks this, so they
	/// cannot drift apart.
	var canRetry: Bool {
		self == .stopped || self == .recoverableError
	}
}

/// Which way a transfer runs.
nonisolated enum FileTransferDirection: Sendable {
	case incoming
	case outgoing

	/// The line under a running transfer's progress bar.
	func progressNotice(
		processedSize: String,
		totalSize: String,
		speed: String,
		peerNickname: String,
		timeRemaining: String?
	) -> String {
		let resource: LocalizedStringResource = switch (self, timeRemaining) {
		case let (.incoming, timeRemaining?):
			.FileTransfer.ofSReceivedFromRemaining(processedSize, totalSize, speed, peerNickname, timeRemaining)
		case (.incoming, nil):
			.FileTransfer.ofSReceived(processedSize, totalSize, speed, peerNickname)
		case let (.outgoing, timeRemaining?):
			.FileTransfer.ofSSentToRemaining(processedSize, totalSize, speed, peerNickname, timeRemaining)
		case (.outgoing, nil):
			.FileTransfer.ofSSent(processedSize, totalSize, speed, peerNickname)
		}

		return String(localized: resource)
	}
}

/// Why a transfer stopped.
nonisolated enum FileTransferFailure: Equatable, Sendable {
	case connectionUnavailable
	case connectTimeout
	case fileHandlerFailed
	case invalidResumePosition
	case noListeningPort
	case notConnectedToIRC
	case oversizedTransfer
	case peerClosedConnection
	/// The peer never answered a RESUME.
	case resumeNotAnswered
	case sourceFileUnreadable
	case sourceIPAddressUnknown
	case storageFull
	case stalled
	/// A transport error that arrived with its own description. Only
	/// ``DCCTransferError/network(_:)`` carries one; every other transport
	/// failure maps to a case above, which is what gives it localized copy.
	case underlying(String)

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
		case .stalled:
			self = .stalled
		}
	}

	/// What the row says went wrong.
	func message(peerNickname: String) -> String {
		let resource = switch self {
		case .connectionUnavailable:
			LocalizedStringResource.FileTransfer.transferWithFailedCouldNotEstablish(peerNickname)
		case .connectTimeout:
			LocalizedStringResource.FileTransfer.transferWithFailedNoAnswer(peerNickname)
		case .fileHandlerFailed:
			LocalizedStringResource.FileTransfer.transferWithFailedFileHandlerThrew(peerNickname)
		case .invalidResumePosition:
			LocalizedStringResource.FileTransfer.transferWithFailedProposedResumePosition(peerNickname)
		case .noListeningPort:
			LocalizedStringResource.FileTransfer.transferWithFailedThereIsNo(peerNickname)
		case .notConnectedToIRC:
			LocalizedStringResource.FileTransfer.transferWithFailedYouAreNot(peerNickname)
		case .oversizedTransfer:
			LocalizedStringResource.FileTransfer.transferFromFailedBecauseTheSender(peerNickname)
		case .peerClosedConnection:
			LocalizedStringResource.FileTransfer.transferWithFailedPeerClosed(peerNickname)
		case .resumeNotAnswered:
			LocalizedStringResource.FileTransfer.transferWithFailedResumeNotAnswered(peerNickname)
		case .sourceFileUnreadable:
			LocalizedStringResource.FileTransfer.transferWithFailedCouldNotRead(peerNickname)
		case .sourceIPAddressUnknown:
			LocalizedStringResource.FileTransfer.transferWithFailedUnknownSourceIp(peerNickname)
		case .storageFull:
			LocalizedStringResource.FileTransfer.transferWithFailedNoSpaceLeft(peerNickname)
		case .stalled:
			LocalizedStringResource.FileTransfer.transferWithFailedStalled(peerNickname)
		case let .underlying(description):
			LocalizedStringResource.FileTransfer.transferWithFailed(peerNickname, description)
		}

		return String(localized: resource)
	}
}

nonisolated extension FileTransferStatus {
	/** How an idle or negotiating transfer reads in its row.

	 Every step between Start and the first byte -- mapping a port, working out
	 this Mac's address, opening the socket -- is one wait from the user's side,
	 and naming each of them separately told them nothing they could act on. */
	func notice(direction: FileTransferDirection, peerNickname: String) -> String? {
		let resource: LocalizedStringResource? = switch (self, direction) {
		case (.stopped, .incoming):
			.FileTransfer.transferFromIsStopped(peerNickname)
		case (.stopped, .outgoing):
			.FileTransfer.transferToIsStopped(peerNickname)
		case (.initializing, _), (.mappingListeningPort, _), (.waitingForLocalIPAddress, _):
			.FileTransfer.preparingTheTransfer
		case (.isListeningAsSender, _), (.waitingForReceiverToAccept, _):
			.FileTransfer.transferToIsReadyWaiting(peerNickname)
		case (.isListeningAsReceiver, _):
			.FileTransfer.transferFromIsReady(peerNickname)
		case (.complete, .incoming):
			.FileTransfer.transferFromIsComplete(peerNickname)
		case (.complete, .outgoing):
			.FileTransfer.transferToIsComplete(peerNickname)
		case (.connecting, _):
			.FileTransfer.statusWhileConnecting(peerNickname)
		case (.waitingForResumeAccept, _):
			.FileTransfer.transferFromWaitingForResponse(peerNickname)
		case (.fatalError, _), (.recoverableError, _), (.receiving, _), (.sending, _):
			nil
		}

		return resource.map { String(localized: $0) }
	}
}
