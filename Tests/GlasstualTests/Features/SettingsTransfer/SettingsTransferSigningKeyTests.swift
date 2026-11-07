// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation
@testable import Glasstual
import Testing

@MainActor
@Suite("SASL ECDSA key and configuration transfer")
struct SettingsTransferSigningKeyTests {
	private static func configuration(withKey stored: String) -> ServerConfig {
		var configuration = ServerConfig(connectionName: "Keyed")
		configuration.pendingSASLSigningKey = .set(stored)
		return configuration
	}

	@Test("Export drops a pending signing key and never encodes it")
	func exportExcludesTheKey() {
		let stored = ECDSASigningKey.storedRepresentation(of: ECDSASigningKey.generate())
		let configuration = Self.configuration(withKey: stored)

		#expect(SettingsSessionArchive.portable(configuration).pendingSASLSigningKey == .unchanged)
		#expect(configuration.pendingSASLSigningKey == .set(stored))

		for includesCommands in [false, true] {
			let dictionary = SettingsSessionArchive.portableDictionary(
				configuration,
				includeConnectCommands: includesCommands
			)
			#expect(String(describing: dictionary).contains(stored) == false)
			#expect(dictionary.keys.contains { $0.lowercased().contains("signingkey") } == false)
		}
		#expect(String(describing: configuration.dictionaryValue).contains(stored) == false)
	}

	@Test("The signing key is a keychain item scoped to the connection")
	func keyIsAKeychainItem() {
		var configuration = Self.configuration(withKey: "stored")

		#expect(configuration.saslSigningKeyKeychainItem == .saslSigningKey(configuration.uniqueIdentifier))
		#expect(configuration.keychainItems.contains(configuration.saslSigningKeyKeychainItem))
		#expect(configuration.pendingKeychainEdits[configuration.saslSigningKeyKeychainItem] == .set("stored"))

		let edits = configuration.pendingKeychainEdits
		configuration.acknowledgeKeychainEdits(edits)

		#expect(configuration.pendingSASLSigningKey == .unchanged)
	}
}
