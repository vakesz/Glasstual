// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/** A SASL mechanism the session can speak.

 The raw value is the name the mechanism goes by on the wire. Servers differ in
 how they capitalise the names they advertise, so names read from the wire are
 matched with ``init(wireName:)`` rather than by raw value. */
nonisolated enum SASLMechanism: String, CaseIterable, Codable, Sendable {
	case external = "EXTERNAL"
	case ecdsaNIST256PChallenge = "ECDSA-NIST256P-CHALLENGE"
	case scramSHA512 = "SCRAM-SHA-512"
	case scramSHA256 = "SCRAM-SHA-256"
	case plain = "PLAIN"

	/// Matches a name the way servers send it, whatever its capitalisation.
	init?(wireName: String) {
		self.init(rawValue: wireName.uppercased())
	}

	var wireName: String {
		rawValue
	}

	/** The order mechanisms are tried in when the user has no preference.

	 Strongest proof first: a certificate or a key proves possession without
	 sending a secret, SCRAM proves knowledge of the password without sending
	 it, and PLAIN sends the password as typed. */
	static let defaultOrder: [SASLMechanism] = [
		.external,
		.ecdsaNIST256PChallenge,
		.scramSHA512,
		.scramSHA256,
		.plain,
	]

	/// What the mechanism signs in with.
	var credential: SASLCredentialKind {
		switch self {
		case .external: .clientCertificate
		case .ecdsaNIST256PChallenge: .signingKey
		case .scramSHA512, .scramSHA256: .passwordProof
		case .plain: .passwordInClear
		}
	}

	/// Where the mechanism sits in ``defaultOrder``; lower is stronger.
	var strength: Int {
		Self.defaultOrder.firstIndex(of: self) ?? Self.defaultOrder.count
	}
}

/// The kind of credential a mechanism uses, which decides where it may be sent.
nonisolated enum SASLCredentialKind: Sendable, Equatable {
	/// The TLS client certificate the connection already presented.
	case clientCertificate
	/// A private key that signs the server's challenge.
	case signingKey
	/// A password the mechanism proves knowledge of without sending it.
	case passwordProof
	/// A password the mechanism sends as typed.
	case passwordInClear
}
