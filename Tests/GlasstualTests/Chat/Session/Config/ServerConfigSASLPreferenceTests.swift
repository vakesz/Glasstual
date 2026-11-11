// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation
@testable import Glasstual
import Testing

@Suite("Server configuration SASL mechanism preference")
struct ServerConfigSASLPreferenceTests {
	private func decode(_ dictionary: [String: Any]) -> ServerConfig? {
		PropertyListModel.decode(
			ServerConfig.self,
			from: [String: PropertyListValue](propertyList: dictionary) ?? [:]
		)
	}

	@Test("A stored name decodes whatever its capitalisation")
	func legacySpellingDecodes() {
		#expect(decode(["saslMechanismPreference": "scram-sha-256"])?.saslMechanismPreference == .scramSHA256)
	}

	@Test("An unknown or empty name decodes as Automatic", arguments: ["FOO", ""])
	func unknownNameIsAutomatic(_ name: String) {
		let config = decode(["saslMechanismPreference": name])
		#expect(config != nil)
		#expect(config?.saslMechanismPreference == nil)
	}

	@Test("The preference and the only-this-mechanism switch round-trip under their keys")
	func preferenceRoundTrips() throws {
		var config = ServerConfig()
		config.saslMechanismPreference = .plain
		config.saslUsesOnlyPreferredMechanism = true

		let encoded = config.dictionaryValue

		#expect(encoded["saslMechanismPreference"]?.string == "PLAIN")
		#expect(encoded["saslUsesOnlyPreferredMechanism"]?.boolean == true)

		let restored = try #require(PropertyListModel.decode(ServerConfig.self, from: encoded))
		#expect(restored.saslMechanismPreference == .plain)
		#expect(restored.saslUsesOnlyPreferredMechanism)
	}

	@Test("Automatic writes no preference and leaves the switch off")
	func automaticWritesNothing() {
		let encoded = ServerConfig().dictionaryValue
		#expect(encoded["saslMechanismPreference"] == nil)
		#expect(encoded["saslUsesOnlyPreferredMechanism"] == nil)
	}
}
