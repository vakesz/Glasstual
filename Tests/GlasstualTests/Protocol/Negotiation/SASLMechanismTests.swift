// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

@testable import Glasstual
import Testing

@Suite("SASL mechanism names")
struct SASLMechanismTests {
	@Test("Wire names are matched whatever their capitalisation", arguments: [
		("scram-sha-256", SASLMechanism.scramSHA256),
		("Plain", .plain),
		("EXTERNAL", .external),
		("ecdsa-NIST256P-challenge", .ecdsaNIST256PChallenge),
	])
	func wireNamesMatchCaseInsensitively(_ name: String, _ expected: SASLMechanism) {
		#expect(SASLMechanism(wireName: name) == expected)
	}

	@Test("Names the session does not speak are rejected", arguments: ["GSSAPI", "", "SCRAM-SHA-1", "PLAIN "])
	func unknownNamesAreRejected(_ name: String) {
		#expect(SASLMechanism(wireName: name) == nil)
	}

	@Test("Every mechanism has its own wire name and appears once in the default order")
	func wireNamesAreUniqueAndOrderIsComplete() {
		let names = SASLMechanism.allCases.map(\.wireName)
		#expect(Set(names).count == names.count)
		#expect(SASLMechanism.defaultOrder.count == SASLMechanism.allCases.count)
		#expect(Set(SASLMechanism.defaultOrder) == Set(SASLMechanism.allCases))
	}
}
