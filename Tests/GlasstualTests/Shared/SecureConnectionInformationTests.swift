// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation
@testable import Glasstual
import Testing

/// The values that replaced loose XPC argument lists have to survive the
/// archiver that carries them across the process boundary.
@Suite("Secure connection information")
struct SecureConnectionInformationTests {
	private func roundTripped(_ value: SecureConnectionInformation) throws -> SecureConnectionInformation {
		let data = try NSKeyedArchiver.archivedData(withRootObject: value, requiringSecureCoding: true)
		let decoded = try NSKeyedUnarchiver.unarchivedObject(
			ofClass: SecureConnectionInformation.self,
			from: data
		)

		return try #require(decoded)
	}

	@Test
	func survivesSecureCoding() throws {
		let chain = [Data([0x01, 0x02]), Data([0x03])]
		let original = SecureConnectionInformation(
			policyName: "irc.example.net",
			protocolVersion: .TLSv13,
			cipherSuite: .AES_256_GCM_SHA384,
			certificateChain: chain,
			trustFailureDescription: "expired"
		)

		let decoded = try roundTripped(original)

		#expect(decoded.policyName == "irc.example.net")
		#expect(decoded.protocolVersion == .TLSv13)
		#expect(decoded.cipherSuite == .AES_256_GCM_SHA384)
		#expect(decoded.certificateChain == chain)
		#expect(decoded.trustFailureDescription == "expired")
	}

	/// A connection that never negotiated TLS used to be five arguments whose
	/// only signal was a nil in the first position.
	@Test
	func survivesSecureCodingWithNothingNegotiated() throws {
		let decoded = try roundTripped(.none)

		#expect(decoded.policyName == nil)
		#expect(decoded.trustFailureDescription == nil)
		#expect(decoded.certificateChain.isEmpty)
		#expect(decoded.protocolVersion == tlsProtocolVersionUnknown)
		#expect(decoded.cipherSuite == tlsCipherSuiteUnknown)
	}
}
