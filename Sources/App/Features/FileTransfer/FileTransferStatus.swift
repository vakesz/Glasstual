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
	/// A secure connection's handshake is waiting for the user to decide about
	/// the peer's certificate.
	case waitingForCertificateDecision
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
		     .waitingForResumeAccept, .waitingForCertificateDecision:
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
	/// The peer's certificate was refused, by the user or for lack of an
	/// answer.
	case peerCertificateRejected
	/// The peer presented no certificate and one is required.
	case peerCertificateRequired
	/// The peer's certificate has a key below the accepted strength.
	case weakPeerCertificate
	/// TLS could not agree with the peer.
	case secureHandshakeFailed(String)
	/// This side's certificate for secure connections could not be loaded.
	case identityUnavailable
	/// A transport error that arrived with its own description. Only
	/// ``DCCTransferError/network(_:)`` carries one; every other transport
	/// failure maps to a case above, which is what gives it localized copy.
	case underlying(String)

	init(_ error: DCCTransferError) {
		switch error {
		case .badParameter, .rejectedPeerAddress:
			self = .connectionUnavailable
		case .peerCertificateRejected:
			self = .peerCertificateRejected
		case .peerCertificateRequired:
			self = .peerCertificateRequired
		case .weakPeerCertificate:
			self = .weakPeerCertificate
		case let .tlsHandshakeFailed(reason):
			self = .secureHandshakeFailed(reason)
		case .identityUnavailable:
			self = .identityUnavailable
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
		let resource: LocalizedStringResource = switch self {
		case .connectionUnavailable:
			.FileTransfer.transferWithFailedCouldNotEstablish(peerNickname)
		case .connectTimeout:
			.FileTransfer.transferWithFailedNoAnswer(peerNickname)
		case .fileHandlerFailed:
			.FileTransfer.transferWithFailedFileHandlerThrew(peerNickname)
		case .invalidResumePosition:
			.FileTransfer.transferWithFailedProposedResumePosition(peerNickname)
		case .noListeningPort:
			.FileTransfer.transferWithFailedThereIsNo(peerNickname)
		case .notConnectedToIRC:
			.FileTransfer.transferWithFailedYouAreNot(peerNickname)
		case .oversizedTransfer:
			.FileTransfer.transferFromFailedBecauseTheSender(peerNickname)
		case .peerClosedConnection:
			.FileTransfer.transferWithFailedPeerClosed(peerNickname)
		case .resumeNotAnswered:
			.FileTransfer.transferWithFailedResumeNotAnswered(peerNickname)
		case .sourceFileUnreadable:
			.FileTransfer.transferWithFailedCouldNotRead(peerNickname)
		case .sourceIPAddressUnknown:
			.FileTransfer.transferWithFailedUnknownSourceIp(peerNickname)
		case .storageFull:
			.FileTransfer.transferWithFailedNoSpaceLeft(peerNickname)
		case .stalled:
			.FileTransfer.transferWithFailedStalled(peerNickname)
		case let .underlying(description):
			.FileTransfer.transferWithFailed(peerNickname, description)
		case .peerCertificateRejected:
			.ConnectionSafety.secureDccCertificateRejected(peerNickname)
		case .peerCertificateRequired:
			.ConnectionSafety.secureDccCertificateRequired(peerNickname)
		case .weakPeerCertificate:
			.ConnectionSafety.secureDccWeakKey(peerNickname)
		case let .secureHandshakeFailed(reason):
			.ConnectionSafety.secureDccHandshakeFailed(peerNickname, reason)
		case .identityUnavailable:
			.ConnectionSafety.secureDccIdentityUnavailable(peerNickname)
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
		case (.waitingForCertificateDecision, _):
			.FileTransfer.waitingForCertificateDecision(peerNickname)
		case (.fatalError, _), (.recoverableError, _), (.receiving, _), (.sending, _):
			nil
		}

		return resource.map { String(localized: $0) }
	}
}
