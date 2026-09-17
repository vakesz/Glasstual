// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
import CocoaExtensions
@testable import Glasstual
import Testing

/// A per-server "Disconnect if SASL authentication fails" option. Without it
/// the client completes registration unauthenticated on 904, 905 or 906, which
/// many networks treat as a security failure.
@Suite("Disconnect on SASL failure")
@MainActor
struct ClientConfigSASLFailureTests {
	private static let key = "disconnectOnSASLFailure"

	@Test("The option is off by default")
	func defaultsToOff() {
		#expect(ClientConfig().disconnectOnSASLFailure == false)
	}

	@Test("The value survives a round trip through the dictionary representation")
	func roundTripsThroughADictionary() throws {
		var config = ClientConfig()
		config.disconnectOnSASLFailure = true

		let dictionary = config.dictionaryValue
		#expect(dictionary[Self.key]?.boolean == true)

		let restored = try #require(PropertyListModel.decode(ClientConfig.self, from: dictionary))
		#expect(restored.disconnectOnSASLFailure)
	}

	@Test("A dictionary without the key reads back as off")
	func absentKeyReadsAsOff() throws {
		var dictionary = ClientConfig().dictionaryValue
		dictionary.removeValue(forKey: Self.key)

		let restored = try #require(PropertyListModel.decode(ClientConfig.self, from: dictionary))
		#expect(restored.disconnectOnSASLFailure == false)
	}

	@Test("An off value is not written to the dictionary")
	func offIsTheDefault() {
		#expect(ClientConfig().dictionaryValue[Self.key] == nil)
	}

	@Test("The numerics that mean SASL was refused are the ones the option acts on")
	func failureNumerics() {
		#expect(ServerNumeric.saslfail.rawValue == 904)
		#expect(ServerNumeric.sasltoolong.rawValue == 905)
		#expect(ServerNumeric.saslaborted.rawValue == 906)
	}

	@Test("The disconnect reason resolves against the string catalog")
	func disconnectReasonIsLocalized() {
		let reason = String(localized: .IRC.saslAuthenticationFailedDisconnecting)
		#expect(reason.isEmpty == false)
		#expect(reason != "sasl-authentication-failed-disconnecting")
	}
}
