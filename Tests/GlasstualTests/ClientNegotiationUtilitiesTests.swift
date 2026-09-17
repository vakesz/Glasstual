// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

@testable import Glasstual
import Testing

@MainActor
@Suite("Client SASL negotiation")
struct ClientNegotiationUtilitiesTests {
	@Test("The mechanism list follows the credentials, the certificate and the preference")
	func supportedMechanismsRespectCredentialsCertificateAndPreference() {
		#expect(
			ClientNegotiationUtilities.supportedSASLMechanisms(
				hasClientCertificate: true,
				externalMechanismDisabled: false,
				hasPassword: true,
				preferredMechanism: "plain"
			) == ["PLAIN", "EXTERNAL", "SCRAM-SHA-256"]
		)
		#expect(
			ClientNegotiationUtilities.supportedSASLMechanisms(
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
			ClientNegotiationUtilities.nextSASLMechanism(
				from: ["SCRAM-SHA-256", "PLAIN"],
				offered: ["plain", "scram-sha-256"],
				tried: ["SCRAM-sha-256"]
			) == "PLAIN"
		)
		#expect(ClientNegotiationUtilities.nextSASLMechanism(
			from: ["PLAIN"],
			offered: ["EXTERNAL"],
			tried: []
		) == nil)
	}

	@Test("An empty payload and one that fills the last chunk both end with a terminator")
	func saslWireChunksTerminateEmptyAndExactLengthPayloads() {
		#expect(ClientNegotiationUtilities.saslWireChunks(for: "") == ["+"])

		let exactLengthChunks = ClientNegotiationUtilities.saslWireChunks(
			for: String(repeating: "a", count: 300)
		)

		#expect(exactLengthChunks.map(\.count) == [400, 1])
		#expect(exactLengthChunks.last == "+")

		let shortChunks = ClientNegotiationUtilities.saslWireChunks(for: "hello")

		#expect(shortChunks == ["aGVsbG8="])
	}
}
