// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing

/// Aborting SASL is only meaningful during an exchange.
@MainActor
struct SASLAbortGuardTests {
	@Test("An unverified success outside SASL negotiation sends nothing and leaves identification alone")
	func abortOutsideNegotiationIsInert() {
		let session = TestServerSession(configDictionary: ["nickname": "me", "username": "me"])
		session.enableCapability(.isIdentifiedWithSASL)

		session.abortUnverifiedSASLSuccess()

		#expect(session.sentLines.contains("AUTHENTICATE *") == false)
		#expect(session.isCapabilityEnabled(.isIdentifiedWithSASL))
	}
}
