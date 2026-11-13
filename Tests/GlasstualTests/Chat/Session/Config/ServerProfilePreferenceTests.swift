// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation
@testable import Glasstual
import Testing

/// The user's own profile on a server is not a secret, so it is stored and
/// carried by a settings transfer.
@MainActor
@Suite("Remembered server profile")
struct ServerProfilePreferenceTests {
	@Test("The profile survives persistence and settings transfer")
	func survivesPersistenceAndTransfer() throws {
		var config = ServerConfig(connectionName: "Example")
		config.serverProfile = ServerProfilePreference(displayName: "Ada Lovelace", avatar: nil, color: "#112233")

		let restored = try #require(PropertyListModel.decode(ServerConfig.self, from: config.dictionaryValue))
		#expect(restored.serverProfile == config.serverProfile)

		let transferred = try SettingsSessionArchive.decode(.array([
			.dictionary(SettingsSessionArchive.portableDictionary(config)),
		]))
		#expect(transferred.first?.serverProfile == config.serverProfile)
	}

	@Test("A connection that never chose a profile stores none")
	func absentByDefault() {
		let config = ServerConfig(connectionName: "Example")

		#expect(config.dictionaryValue[ServerConfig.CodingKeys.serverProfile.rawValue] == nil)
	}

	@Test("An import with an unknown profile field is refused")
	func unknownFieldRefused() {
		var config = ServerConfig(connectionName: "Example")
		config.serverProfile = ServerProfilePreference(displayName: "Ada")
		var dictionary = SettingsSessionArchive.portableDictionary(config)
		dictionary[ServerConfig.CodingKeys.serverProfile.rawValue] = .dictionary(["pronouns": .string("they")])

		#expect(throws: SettingsTransferError.self) {
			try SettingsSessionArchive.decode(.array([.dictionary(dictionary)]))
		}
	}
}
