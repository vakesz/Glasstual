// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
import CocoaExtensions
@testable import Glasstual
import Testing

@MainActor
@Suite("Server sidebar identity persistence")
struct ServerIdentityStyleTests {
	@Test("Existing configurations keep the default identity without adding archive fields")
	func existingConfigurationsKeepDefaults() throws {
		let config = ServerConfig(connectionName: "Libera.Chat")
		let dictionary = config.dictionaryValue
		#expect(dictionary[ServerConfig.CodingKeys.sidebarColor.rawValue] == nil)
		#expect(dictionary[ServerConfig.CodingKeys.sidebarIcon.rawValue] == nil)
		let restored = try #require(PropertyListModel.decode(ServerConfig.self, from: dictionary))
		#expect(restored.sidebarIdentity == ServerIdentityStyle())
	}

	@Test("Server color and symbol survive persistence and settings transfer")
	func identitySurvivesPersistenceAndTransfer() throws {
		var config = ServerConfig(connectionName: "Swift")
		config.sidebarIdentity = ServerIdentityStyle(color: .purple, icon: .code)
		let restored = try #require(PropertyListModel.decode(ServerConfig.self, from: config.dictionaryValue))
		#expect(restored.sidebarIdentity == config.sidebarIdentity)
		let transferred = try SettingsSessionArchive.decode(.array([
			.dictionary(SettingsSessionArchive.portableDictionary(config)),
		]))
		#expect(transferred.first?.sidebarIdentity == config.sidebarIdentity)
	}

	@Test("Malformed stored choices fall back independently, while imports reject them",
	      arguments: [ServerConfig.CodingKeys.sidebarColor, .sidebarIcon])
	func malformedChoices(_ key: ServerConfig.CodingKeys) throws {
		var config = ServerConfig(connectionName: "Swift")
		config.sidebarIdentity = ServerIdentityStyle(color: .teal, icon: .leaf)
		var dictionary = config.dictionaryValue
		dictionary[key.rawValue] = .string("unknown-choice")
		let restored = try #require(PropertyListModel.decode(ServerConfig.self, from: dictionary))
		#expect(restored.sidebarIdentity.color == (key == .sidebarColor ? .standard : .teal))
		#expect(restored.sidebarIdentity.icon == (key == .sidebarIcon ? .network : .leaf))
		#expect(throws: SettingsTransferError.self) {
			try SettingsSessionArchive.decode(.array([.dictionary(dictionary)]))
		}
	}

	@Test("Every offered symbol can be rendered by AppKit", arguments: ServerIdentityStyle.Icon.allCases)
	func symbolExists(_ icon: ServerIdentityStyle.Icon) {
		#expect(NSImage(systemSymbolName: icon.symbolName, accessibilityDescription: nil) != nil)
	}

	@Test("Server Properties submits its edited identity without mutating the original")
	func sheetEditsDraft() throws {
		var original = ServerConfig(connectionName: "Swift")
		original.nickname = "tester"
		original.username = "tester"
		original.serverList = [ServerEndpoint(serverAddress: "irc.example.test")]
		let model = ServerPropertiesModel(config: original)
		model.config.sidebarIdentity = ServerIdentityStyle(color: .blue, icon: .terminal)
		let submitted = try #require(model.submittedConfig())
		#expect(submitted.sidebarIdentity == ServerIdentityStyle(color: .blue, icon: .terminal))
		#expect(original.sidebarIdentity == ServerIdentityStyle())
	}
}
