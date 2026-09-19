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
}
