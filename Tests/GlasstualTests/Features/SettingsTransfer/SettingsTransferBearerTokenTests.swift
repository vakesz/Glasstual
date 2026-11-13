// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation
@testable import Glasstual
import Testing

@MainActor
@Suite("SASL OAuth token and configuration transfer")
struct SettingsTransferBearerTokenTests {
	private static let token = "secret-oauth-token~123"

	private static func configuration() -> ServerConfig {
		var configuration = ServerConfig(connectionName: "Token")
		configuration.pendingSASLBearerToken = .set(token)
		return configuration
	}

	@Test("Export drops a pending token and never encodes it")
	func exportExcludesTheToken() {
		let configuration = Self.configuration()

		#expect(SettingsSessionArchive.portable(configuration).pendingSASLBearerToken == .unchanged)
		for includesCommands in [false, true] {
			let dictionary = SettingsSessionArchive.portableDictionary(configuration, includeConnectCommands: includesCommands)
			#expect(String(describing: dictionary).contains(Self.token) == false)
		}
		#expect(String(describing: configuration.dictionaryValue).contains(Self.token) == false)
	}

	@Test("The token is a keychain item the edits, items and acknowledgement all cover")
	func tokenIsAKeychainItem() {
		var configuration = Self.configuration()
		let item = configuration.saslBearerTokenKeychainItem

		#expect(item == .saslBearerToken(configuration.uniqueIdentifier))
		#expect(item.service == "glasstual.sasl-oauthbearer.\(configuration.uniqueIdentifier)")
		#expect(configuration.keychainItems.contains(item))
		#expect(configuration.pendingKeychainEdits[item] == .set(Self.token))

		configuration.acknowledgeKeychainEdits(configuration.pendingKeychainEdits)
		#expect(configuration.pendingSASLBearerToken == .unchanged)
	}

	@Test("A duplicate carries the token across and a re-identified copy drops it")
	func copyingTheConfiguration() {
		let configuration = Self.configuration()

		#expect(configuration.uniqueCopy().pendingSASLBearerToken == .set(Self.token))
		#expect(configuration.reidentified(derivedFrom: "import").pendingSASLBearerToken == .unchanged)
	}
}
