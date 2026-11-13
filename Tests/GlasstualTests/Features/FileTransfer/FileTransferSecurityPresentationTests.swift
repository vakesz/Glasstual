// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Network
import Testing

/// What a secure transfer or chat shows: the lock, what it says, and when its
/// certificate can be shown.
@Suite("Secure DCC presentation")
@MainActor
struct FileTransferSecurityPresentationTests {
	private let center = FileTransferStore(addressSource: { nil })

	private func transfer(security: DCCOfferSecurity, on session: ServerSession) throws -> FileTransfer {
		let transfer = try #require(FileTransfer.receiver(
			for: session, center: center, nickname: "alice", address: "203.0.113.5", port: 1234,
			filename: "file.bin", filesize: 1024, token: nil, security: security
		))
		center.model.add(transfer)
		return transfer
	}

	private func session(peer: DCCPeerCertificate?) -> DCCSecureSessionInfo {
		DCCSecureSessionInfo(protocolVersion: .TLSv13, cipherSuite: .AES_128_GCM_SHA256, peer: peer)
	}

	private func certificate() throws -> DCCPeerCertificate {
		try #require(DCCPeerCertificate(der: PeerCertificateFixture.ellipticCurve()))
	}

	@Test("A plain transfer has no lock; a secure one is pending until it connects")
	func indicatorFollowsTheConnection() throws {
		let session = TestServerSession()
		let plain = try transfer(security: .plain, on: session)
		let secure = try transfer(security: .secure, on: session)

		#expect(FileTransferRowPresentation(transfer: plain).security == nil)
		#expect(FileTransferRowPresentation(transfer: secure).security?.indicator == .pending)
		#expect(FileTransferRowPresentation(transfer: secure).security?.accessibilityLabel
			== String(localized: .FileTransfer.secureIndicatorPending))

		secure.secureSession = try self.session(peer: certificate())
		#expect(FileTransferRowPresentation(transfer: secure).security?.indicator == .verified)

		secure.secureSession = self.session(peer: nil)
		let unverified = try #require(FileTransferRowPresentation(transfer: secure).security)
		#expect(unverified.indicator == .unverified)
		#expect(unverified.indicator.symbolName == "lock.trianglebadge.exclamationmark")
		#expect(unverified.accessibilityLabel == String(localized: .FileTransfer.secureIndicatorUnverified))
		plain.prepareForPermanentDestruction()
		secure.prepareForPermanentDestruction()
	}

	@Test("The lock's help names the protocol and the peer's fingerprint")
	func detailsNameTheFingerprint() throws {
		let peer = try certificate()
		let security = FileTransferRowPresentation.Security(indicator: .verified, session: session(peer: peer))

		#expect(security.details.contains("TLS 1.3"))
		#expect(security.details.contains(peer.fingerprint.formatted))
	}

	@Test("Show Certificate is offered for exactly one transfer whose peer presented one")
	func showCertificateAvailability() throws {
		let session = TestServerSession()
		let first = try transfer(security: .secure, on: session)
		let second = try transfer(security: .secure, on: session)
		let both: Set = [first.uniqueIdentifier, second.uniqueIdentifier]

		#expect(center.model.canPerform(.showCertificate, on: [first.uniqueIdentifier]) == false)
		first.secureSession = self.session(peer: nil)
		#expect(center.model.canPerform(.showCertificate, on: [first.uniqueIdentifier]) == false)
		first.secureSession = try self.session(peer: certificate())
		second.secureSession = try self.session(peer: certificate())
		#expect(center.model.canPerform(.showCertificate, on: [first.uniqueIdentifier]))
		#expect(center.model.canPerform(.showCertificate, on: both) == false)
		#expect(try #require(first.secureSession?.peer).displayTrust() != nil)
		first.prepareForPermanentDestruction()
		second.prepareForPermanentDestruction()
	}

	@Test("A secure direct chat says so under the window title")
	func secureDirectChatSubtitle() throws {
		let session = TestServerSession()
		let conversation = try #require(session.prepareDirectChatConversation(forNickname: "alice"))
		conversation.directChatConnection = DirectChatSession.connection(
			toPeer: "alice", address: "203.0.113.5", port: 5000, secure: true, onSession: session
		)

		let subtitle = MainWindowTitleContent(session: session, conversation: conversation).subtitle

		#expect(subtitle.contains(String(localized: .MainWindow.encryptedDirectChat)))
		#expect(conversation.directChatConnection?.securityIndicator == .pending)
	}

	@Test("A plain direct chat has no lock")
	func plainDirectChat() {
		let session = TestServerSession()
		let chat = DirectChatSession.connection(toPeer: "alice", address: "203.0.113.5", port: 5000, onSession: session)

		#expect(chat.securityIndicator == nil)
	}

	@Test("The secure connection settings default to taking secure offers, offering plain and not requiring a certificate")
	func settingDefaults() {
		#expect(SettingsKeys.FileTransfers.acceptsSecureOffers.defaultValue)
		#expect(SettingsKeys.FileTransfers.offersAreSecure.defaultValue == false)
		#expect(SettingsKeys.FileTransfers.requirePeerCertificate.defaultValue == false)
		for key in [
			SettingsKeys.FileTransfers.acceptsSecureOffers,
			SettingsKeys.FileTransfers.offersAreSecure,
			SettingsKeys.FileTransfers.requirePeerCertificate,
		] {
			#expect(SettingsKeys.FileTransfers.all.contains { $0.name == key.name })
			#expect(key.traits.contains(.excludedFromExport) == false)
		}
	}
}
