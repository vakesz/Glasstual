// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation
import Network
import Security

/// Whether a DCC connection runs over TLS, and how it decides about the peer.
nonisolated enum DCCSecurity: Sendable {
	case plain
	case tls(DCCTLSConfiguration)
}

/// What a secure DCC connection presents and how it judges what it is shown.
nonisolated struct DCCTLSConfiguration: Sendable {
	/// How long the decision about a peer may take. A person may be deciding,
	/// so this is long; past it the peer is refused.
	static let defaultDecisionTimeout: Duration = .seconds(120)
	/// How long the handshake itself may take, not counting the decision.
	static let defaultHandshakeTimeout: Duration = .seconds(30)

	var identity: DCCLocalIdentity
	/// Refuse a TLS client that presents no certificate rather than letting it
	/// in encrypted but unverified.
	var requirePeerCertificate: Bool
	var verifier: DCCPeerVerifier
	var decisionTimeout: Duration
	var handshakeTimeout: Duration

	init(
		identity: DCCLocalIdentity,
		requirePeerCertificate: Bool,
		verifier: DCCPeerVerifier,
		decisionTimeout: Duration = Self.defaultDecisionTimeout,
		handshakeTimeout: Duration = Self.defaultHandshakeTimeout
	) {
		self.identity = identity
		self.requirePeerCertificate = requirePeerCertificate
		self.verifier = verifier
		self.decisionTimeout = decisionTimeout
		self.handshakeTimeout = handshakeTimeout
	}

	/// The most a secure connection may take to become usable once the peer
	/// is reached: the handshake and the decision about the peer.
	var establishmentTimeout: Duration {
		handshakeTimeout + decisionTimeout
	}
}

/** Decides whether the peer of a secure DCC connection may proceed.

 It is asked before a single application byte is read or written. For a
 presented certificate that is during the handshake, which stays suspended
 until the answer; for a TLS client that presented none it is right after the
 handshake, with `nil`. `false` closes the connection. */
nonisolated struct DCCPeerVerifier: Sendable {
	let decide: @Sendable (DCCPeerCertificate?) async -> Bool
}

/// What a secure DCC connection negotiated, reported once it is usable.
nonisolated struct DCCSecureSessionInfo: Equatable, Sendable {
	let protocolVersion: tls_protocol_version_t
	let cipherSuite: tls_ciphersuite_t
	/// `nil` when the peer, as a TLS client, presented no certificate.
	let peer: DCCPeerCertificate?

	/// The protocol as people write it, such as "TLS 1.3".
	var protocolName: String {
		switch protocolVersion {
		case .TLSv13: "TLS 1.3"
		case .TLSv12: "TLS 1.2"
		default: "TLS"
		}
	}

	/// The negotiated cipher suite's standard name.
	var cipherSuiteName: String {
		SecureTransportSupport.description(forCipherSuite: cipherSuite)
	}
}

/// How far a secure DCC transfer or chat has got, as an indicator shows it.
nonisolated enum DCCSecurityIndicator: Equatable, Sendable {
	/// Offered or accepted over TLS, not connected yet.
	case pending
	/// Connected, and the peer's certificate was trusted.
	case verified
	/// Connected and encrypted, but the peer presented no certificate.
	case unverified

	/// `nil` for a plain connection.
	init?(isSecure: Bool, session: DCCSecureSessionInfo?) {
		guard isSecure else { return nil }
		guard let session else {
			self = .pending
			return
		}
		self = session.peer == nil ? .unverified : .verified
	}

	/// The SF Symbol an indicator draws.
	var symbolName: String {
		switch self {
		case .pending, .verified: "lock.fill"
		case .unverified: "lock.trianglebadge.exclamationmark"
		}
	}
}

extension DCCPeerCertificate {
	/// The certificate as a trust object the certificate sheet can show. Nothing
	/// is evaluated: peers are self-signed and judged by fingerprint.
	func displayTrust() -> SecTrust? {
		guard let certificate = SecCertificateCreateWithData(nil, der as CFData) else { return nil }
		var trust: SecTrust?
		guard SecTrustCreateWithCertificates(certificate, SecPolicyCreateBasicX509(), &trust) == errSecSuccess else {
			return nil
		}
		return trust
	}
}
