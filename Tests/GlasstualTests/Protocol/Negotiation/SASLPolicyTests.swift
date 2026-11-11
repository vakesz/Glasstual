// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

@testable import Glasstual
import Testing

@Suite("SASL mechanism policy")
struct SASLPolicyTests {
	private nonisolated static let everything = SASLCredentialInventory(
		hasClientCertificate: true,
		hasPassword: true,
		hasSigningKey: true
	)

	struct AvailabilityCase: Sendable, CustomTestStringConvertible {
		let mechanism: SASLMechanism
		let inventory: SASLCredentialInventory
		let transport: SASLTransportAssurance
		let expected: SASLAvailability
		var testDescription: String {
			"\(mechanism.wireName) over \(transport)"
		}
	}

	@Test("Availability follows the credential and the transport", arguments: [
		AvailabilityCase(mechanism: .plain, inventory: everything, transport: .plaintext(clearCredentialsAllowed: true), expected: .usable),
		AvailabilityCase(
			mechanism: .plain,
			inventory: everything,
			transport: .plaintext(clearCredentialsAllowed: false),
			expected: .unavailable(.clearTextNotPermitted)
		),
		AvailabilityCase(mechanism: .plain, inventory: everything, transport: .verifiedTLS, expected: .usable),
		AvailabilityCase(
			mechanism: .plain,
			inventory: everything,
			transport: .unverifiedTLS(consented: false, mayAsk: true),
			expected: .needsConsent
		),
		AvailabilityCase(
			mechanism: .plain,
			inventory: everything,
			transport: .unverifiedTLS(consented: false, mayAsk: false),
			expected: .unavailable(.clearTextNotPermitted)
		),
		AvailabilityCase(
			mechanism: .plain,
			inventory: everything,
			transport: .unverifiedTLS(consented: true, mayAsk: false),
			expected: .usable
		),
		AvailabilityCase(
			mechanism: .scramSHA256,
			inventory: everything,
			transport: .plaintext(clearCredentialsAllowed: false),
			expected: .usable
		),
		AvailabilityCase(
			mechanism: .scramSHA256,
			inventory: SASLCredentialInventory(),
			transport: .verifiedTLS,
			expected: .unavailable(.noPassword)
		),
		AvailabilityCase(
			mechanism: .external,
			inventory: SASLCredentialInventory(hasClientCertificate: true, externalMechanismDisabled: true),
			transport: .verifiedTLS,
			expected: .unavailable(.externalDisabled)
		),
		AvailabilityCase(
			mechanism: .external,
			inventory: SASLCredentialInventory(),
			transport: .verifiedTLS,
			expected: .unavailable(.noClientCertificate)
		),
		AvailabilityCase(
			mechanism: .ecdsaNIST256PChallenge,
			inventory: SASLCredentialInventory(hasPassword: true),
			transport: .verifiedTLS,
			expected: .unavailable(.noSigningKey)
		),
	])
	func availabilityFollowsCredentialAndTransport(_ example: AvailabilityCase) {
		#expect(SASLPolicy.availability(
			of: example.mechanism,
			inventory: example.inventory,
			transport: example.transport,
			withholdsAccountCredentials: false
		) == example.expected)
	}

	@Test("Every account credential is withheld from a host outside the configured servers", arguments: SASLMechanism.allCases)
	func withheldCredentialsMakeEveryMechanismUnavailable(_ mechanism: SASLMechanism) {
		#expect(SASLPolicy.availability(
			of: mechanism,
			inventory: Self.everything,
			transport: .verifiedTLS,
			withholdsAccountCredentials: true
		) == .unavailable(.accountCredentialsWithheld))
	}

	@Test("Without a preference the mechanisms come strongest first")
	func defaultOrderIsStrongestFirst() {
		#expect(SASLPolicy.supportedMechanisms(
			inventory: Self.everything,
			transport: .verifiedTLS,
			withholdsAccountCredentials: false,
			preferred: nil
		) == [.external, .ecdsaNIST256PChallenge, .scramSHA512, .scramSHA256, .plain])
	}

	@Test("A preference moves to the front without dropping the others")
	func preferenceMovesToFront() {
		#expect(SASLPolicy.supportedMechanisms(
			inventory: Self.everything,
			transport: .verifiedTLS,
			withholdsAccountCredentials: false,
			preferred: .plain
		) == [.plain, .external, .ecdsaNIST256PChallenge, .scramSHA512, .scramSHA256])
	}

	@Test("A mechanism waiting for consent stays in the list")
	func consentMechanismStays() {
		#expect(SASLPolicy.supportedMechanisms(
			inventory: SASLCredentialInventory(hasPassword: true),
			transport: .unverifiedTLS(consented: false, mayAsk: true),
			withholdsAccountCredentials: false,
			preferred: nil
		) == [.scramSHA512, .scramSHA256, .plain])
	}

	@Test("An unusable preference is ignored, unless it is the only mechanism allowed")
	func unusablePreference() {
		let inventory = SASLCredentialInventory(hasPassword: true)
		#expect(SASLPolicy.supportedMechanisms(
			inventory: inventory,
			transport: .verifiedTLS,
			withholdsAccountCredentials: false,
			preferred: .external
		) == [.scramSHA512, .scramSHA256, .plain])
		#expect(SASLPolicy.supportedMechanisms(
			inventory: inventory,
			transport: .verifiedTLS,
			withholdsAccountCredentials: false,
			preferred: .external,
			onlyPreferred: true
		).isEmpty)
	}

	@Test("SCRAM-SHA-512 sorts ahead of SCRAM-SHA-256, and a preference moves SHA-256 back in front")
	func scramSHA512SortsFirst() {
		let inventory = SASLCredentialInventory(hasPassword: true)
		#expect(SASLPolicy.supportedMechanisms(
			inventory: inventory,
			transport: .verifiedTLS,
			withholdsAccountCredentials: false,
			preferred: nil
		).prefix(2) == [.scramSHA512, .scramSHA256])
		#expect(SASLPolicy.supportedMechanisms(
			inventory: inventory,
			transport: .verifiedTLS,
			withholdsAccountCredentials: false,
			preferred: .scramSHA256
		) == [.scramSHA256, .scramSHA512, .plain])
	}

	@Test("Use Only This Mechanism leaves nothing to fall back to")
	func onlyPreferredStopsFallback() {
		#expect(SASLPolicy.supportedMechanisms(
			inventory: Self.everything,
			transport: .verifiedTLS,
			withholdsAccountCredentials: false,
			preferred: .scramSHA256,
			onlyPreferred: true
		) == [.scramSHA256])
	}

	@Test("The next mechanism skips tried ones, unknown names and mechanisms that were not offered")
	func nextMechanismSkipsTriedUnknownAndUnoffered() {
		let supported: [SASLMechanism] = [.ecdsaNIST256PChallenge, .scramSHA256, .plain]

		#expect(SASLPolicy.nextMechanism(from: supported, offered: ["GSSAPI", "plain"], tried: []) == .plain)
		#expect(SASLPolicy.nextMechanism(
			from: supported,
			offered: ["ecdsa-nist256p-challenge", "PLAIN"],
			tried: [.ecdsaNIST256PChallenge]
		) == .plain)
		#expect(SASLPolicy.nextMechanism(from: supported, offered: ["EXTERNAL"], tried: []) == nil)
	}

	@Test("An empty offer means every supported mechanism may be tried")
	func emptyOfferMeansAny() {
		#expect(SASLPolicy.nextMechanism(from: [.scramSHA256, .plain], offered: [], tried: []) == .scramSHA256)
		#expect(SASLPolicy.nextMechanism(from: [.scramSHA256, .plain], offered: [], tried: [.scramSHA256]) == .plain)
	}

	@Test("An empty payload and one that fills the last chunk both end with a terminator")
	func saslWireChunksTerminateEmptyAndExactLengthPayloads() {
		#expect(SASLPolicy.wireChunks(for: "") == ["+"])

		let exactLengthChunks = SASLPolicy.wireChunks(for: String(repeating: "a", count: 300))

		#expect(exactLengthChunks.map(\.count) == [400, 1])
		#expect(exactLengthChunks.last == "+")
		#expect(SASLPolicy.wireChunks(for: "hello") == ["aGVsbG8="])
	}
}
