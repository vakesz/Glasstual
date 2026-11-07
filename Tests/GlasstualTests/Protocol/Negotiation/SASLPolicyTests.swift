// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

@testable import Glasstual
import Testing

@MainActor
@Suite("Server session SASL negotiation")
struct SASLPolicyTests {
	@Test("The mechanism list follows the credentials, the certificate and the preference")
	func supportedMechanismsRespectCredentialsCertificateAndPreference() {
		#expect(
			SASLPolicy.supportedMechanisms(
				hasClientCertificate: true,
				externalMechanismDisabled: false,
				hasPassword: true,
				preferredMechanism: "plain"
			) == ["PLAIN", "EXTERNAL", "SCRAM-SHA-256"]
		)
		#expect(
			SASLPolicy.supportedMechanisms(
				hasClientCertificate: true,
				externalMechanismDisabled: true,
				hasPassword: false,
				preferredMechanism: nil
			) == []
		)
	}

	@Test("The next mechanism matches the offered and tried lists without regard to case")
	func nextMechanismMatchesServerAndTriedListsCaseInsensitively() {
		#expect(
			SASLPolicy.nextMechanism(
				from: ["SCRAM-SHA-256", "PLAIN"],
				offered: ["plain", "scram-sha-256"],
				tried: ["SCRAM-sha-256"]
			) == "PLAIN"
		)
		#expect(SASLPolicy.nextMechanism(
			from: ["PLAIN"],
			offered: ["EXTERNAL"],
			tried: []
		) == nil)
	}

	@Test("An empty payload and one that fills the last chunk both end with a terminator")
	func saslWireChunksTerminateEmptyAndExactLengthPayloads() {
		#expect(SASLPolicy.wireChunks(for: "") == ["+"])

		let exactLengthChunks = SASLPolicy.wireChunks(
			for: String(repeating: "a", count: 300)
		)

		#expect(exactLengthChunks.map(\.count) == [400, 1])
		#expect(exactLengthChunks.last == "+")

		let shortChunks = SASLPolicy.wireChunks(for: "hello")

		#expect(shortChunks == ["aGVsbG8="])
	}

	@Test("A configured key is tried after EXTERNAL and before either password mechanism")
	func signingKeyComesAheadOfPasswords() {
		#expect(
			SASLPolicy.supportedMechanisms(
				hasClientCertificate: true,
				externalMechanismDisabled: false,
				hasPassword: true,
				hasSigningKey: true,
				preferredMechanism: nil
			) == ["EXTERNAL", "ECDSA-NIST256P-CHALLENGE", "SCRAM-SHA-256", "PLAIN"]
		)
		#expect(
			SASLPolicy.supportedMechanisms(
				hasClientCertificate: false,
				externalMechanismDisabled: false,
				hasPassword: true,
				hasSigningKey: true,
				sendsPasswordInClear: false,
				preferredMechanism: nil
			) == ["ECDSA-NIST256P-CHALLENGE", "SCRAM-SHA-256"]
		)
	}

	@Test("A key alone is enough to sign in, and a stated preference still wins")
	func signingKeyNeedsNoPassword() {
		#expect(
			SASLPolicy.supportedMechanisms(
				hasClientCertificate: false,
				externalMechanismDisabled: false,
				hasPassword: false,
				hasSigningKey: true,
				preferredMechanism: nil
			) == ["ECDSA-NIST256P-CHALLENGE"]
		)
		#expect(
			SASLPolicy.supportedMechanisms(
				hasClientCertificate: false,
				externalMechanismDisabled: false,
				hasPassword: true,
				hasSigningKey: true,
				preferredMechanism: "plain"
			) == ["PLAIN", "ECDSA-NIST256P-CHALLENGE", "SCRAM-SHA-256"]
		)
	}

	@Test("A refused key falls back to the next mechanism the server offers")
	func refusedKeyFallsBack() {
		let supported = ["ECDSA-NIST256P-CHALLENGE", "SCRAM-SHA-256", "PLAIN"]

		#expect(
			SASLPolicy.nextMechanism(from: supported, offered: [], tried: []) == "ECDSA-NIST256P-CHALLENGE"
		)
		#expect(
			SASLPolicy.nextMechanism(
				from: supported,
				offered: ["ecdsa-nist256p-challenge", "plain"],
				tried: ["ECDSA-NIST256P-CHALLENGE"]
			) == "PLAIN"
		)
		#expect(
			SASLPolicy.nextMechanism(from: supported, offered: ["PLAIN"], tried: []) == "PLAIN"
		)
	}
}
