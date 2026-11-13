// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing

/// What a secure transfer keeps, what answers it accepts, and how it reads
/// while the user decides about the peer and once it has failed.
@Suite("Secure file transfer negotiation")
@MainActor
struct FileTransferSecureNegotiationTests {
	private let center = FileTransferStore(addressSource: { nil })

	private func offer(security: DCCOfferSecurity, on session: ServerSession) throws -> FileTransfer {
		let offer = try #require(FileTransfer.receiver(
			for: session, center: center, nickname: "alice", address: "203.0.113.5", port: 1234,
			filename: "file.bin", filesize: 1024, token: "42", security: security
		))
		offer.isSender = true
		offer.transferStatus = .waitingForReceiverToAccept
		center.model.add(offer)
		return offer
	}

	@Test("A reverse offer is only answered by a reply of its own kind", arguments: [
		(DCCOfferSecurity.secure, DCCOfferSecurity.plain, false),
		(.plain, .secure, false),
		(.secure, .secure, true),
		(.plain, .plain, true),
	])
	func replyMustMatchKind(offered: DCCOfferSecurity, replied: DCCOfferSecurity, accepted: Bool) throws {
		let session = TestServerSession()
		let transfer = try offer(security: offered, on: session)

		#expect(center.sentOfferAccepted(
			withToken: "42", on: session, peerNickname: "alice", filename: "file.bin",
			address: "203.0.113.9", port: 5000, filesize: 1024, security: replied
		) == accepted)
		#expect(transfer.security == offered)
		transfer.prepareForPermanentDestruction()
	}

	@Test("A secure offer is listed as a secure receiver")
	func secureReceiver() throws {
		let session = TestServerSession()
		let identifier = try #require(center.addReceiver(
			for: session, nickname: "alice", address: "203.0.113.5", port: 1234,
			filename: "file.bin", filesize: 1024, token: nil, security: .secure, peerIsKnown: false
		))

		let transfer = try #require(center.fileTransfer(withUniqueIdentifier: identifier))
		#expect(transfer.security == .secure)
		transfer.prepareForPermanentDestruction()
	}

	@Test("Waiting for a certificate decision is negotiating, and the row says whose")
	func waitingStatus() {
		let status = FileTransferStatus.waitingForCertificateDecision

		#expect(status.isNegotiating)
		#expect(status.isRunning)
		#expect(status.canRetry == false)
		#expect(status.notice(direction: .incoming, peerNickname: "alice")
			== String(localized: .FileTransfer.waitingForCertificateDecision("alice")))
	}

	@Test("A row goes back to what it said once the decision is made")
	func awaitingDecisionRestores() throws {
		let session = TestServerSession()
		let transfer = try offer(security: .secure, on: session)
		transfer.transferStatus = .connecting

		transfer.noteAwaitingCertificateDecision(true)
		#expect(transfer.transferStatus == .waitingForCertificateDecision)
		transfer.noteAwaitingCertificateDecision(false)

		#expect(transfer.transferStatus == .connecting)
		transfer.prepareForPermanentDestruction()
	}

	@Test("A transfer that is not negotiating is not marked as waiting")
	func awaitingDecisionNeedsNegotiation() throws {
		let session = TestServerSession()
		let transfer = try offer(security: .secure, on: session)
		transfer.transferStatus = .stopped

		transfer.noteAwaitingCertificateDecision(true)

		#expect(transfer.transferStatus == .stopped)
		transfer.prepareForPermanentDestruction()
	}

	@Test("Each secure failure keeps its own reason and wording", arguments: [
		(DCCTransferError.peerCertificateRejected, FileTransferFailure.peerCertificateRejected),
		(.peerCertificateRequired, .peerCertificateRequired),
		(.weakPeerCertificate, .weakPeerCertificate),
		(.tlsHandshakeFailed("bad record"), .secureHandshakeFailed("bad record")),
		(.identityUnavailable, .identityUnavailable),
	])
	func secureFailures(error: DCCTransferError, failure: FileTransferFailure) throws {
		#expect(FileTransferFailure(error) == failure)
		let expected = try #require(ConnectionSafetyStrings.SecureDCC.message(for: error, peer: "alice"))
		#expect(failure.message(peerNickname: "alice") == expected)
	}

	@Test("A failure any connection can have has no secure wording")
	func plainFailureHasNoSecureWording() {
		#expect(ConnectionSafetyStrings.SecureDCC.message(for: .closedByPeer, peer: "alice") == nil)
	}
}
