import CocoaExtensions
import Foundation
@testable import Glasstual
import GlasstualPluginKit
import Testing

@MainActor
@Suite("Client configuration persistence")
struct IRCClientConfigMigrationTests {
	private func decode(_ dictionary: [String: Any]) throws -> ClientConfig {
		try #require(PropertyListModel.decode(ClientConfig.self, from: dictionary))
	}

	@Test("A configuration with nothing but a version carries the documented defaults")
	func defaultsMatchPersistedConfigurationContract() throws {
		let config = try decode(["dictionaryVersion": 710])

		#expect(config.autoConnect == false)
		#expect(config.autoReconnect == false)
		#expect(config.autoSleepModeDisconnect)
		#expect(config.performPongTimer)
		#expect(config.sendWhoCommandRequestsToChannels)
		#expect(config.validateServerCertificateChain)
		#expect(config.addressType == .default)
		#expect(config.proxyType == .automatic)
		#expect(config.proxyPort == 1080)
		#expect(config.floodControlDelayTimerInterval == 2)
		#expect(config.floodControlMaximumMessages == 6)
		#expect(config.connectionName.isEmpty == false)
		#expect(config.uniqueIdentifier.isEmpty == false)
	}

	@Test("Writing a configuration out and reading it back preserves every current key")
	func dictionaryRoundTripPreservesCurrentSchema() throws {
		let input: [String: Any] = [
			"dictionaryVersion": 710,
			"connectionName": "Libera Chat",
			"nickname": "swift-user",
			"autoConnect": true,
			"addressType": IRCConnectionAddressType.v6.rawValue,
			"proxyType": IRCConnectionProxyType.socks5.rawValue,
			"proxyAddress": "proxy.example.test",
			"proxyPort": 1081,
			"serverList": [[
				"serverAddress": "irc.example.test",
				"serverPort": 6697,
				"prefersSecuredConnection": true,
			]],
			"channelList": [[
				"channelName": "#swift",
				"channelType": ChannelType.channel.rawValue,
			]],
		]

		let config = try decode(input)
		let restored = try decode(config.dictionaryValue)

		#expect(restored.connectionName == "Libera Chat")
		#expect(restored.nickname == "swift-user")
		#expect(restored.autoConnect)
		#expect(restored.addressType == .v6)
		#expect(restored.proxyType == .socks5)
		#expect(restored.proxyAddress == "proxy.example.test")
		#expect(restored.proxyPort == 1081)
		#expect(restored.serverList.first?.serverAddress == "irc.example.test")
		#expect(restored.serverList.first?.serverPort == 6697)
		#expect(restored.channelList.first?.channelName == "#swift")
	}

	@Test("A nested channel survives decoding and copying")
	func nestedChannelSurvivesDecodingAndCopying() throws {
		let config = try decode([
			"dictionaryVersion": 710,
			"channelList": [[
				"channelName": "#runtime-dispatch",
				"channelType": ChannelType.channel.rawValue,
			]],
		])

		let copy = config
		let channel = try #require(copy.channelList.first)

		#expect(channel.channelName == "#runtime-dispatch")
		#expect(channel.type == .channel)
	}

	/// A duplicate mints new identifiers all the way down, and carries the
	/// secrets across so the identifier change does not lose them.
	@Test("A unique copy renames every identity and keeps the secrets")
	func uniqueCopyRenamesEveryIdentityAndKeepsSecrets() {
		var config = ClientConfig(connectionName: "SwiftNet")
		config.nicknamePassword = "nick-password"
		config.proxyPassword = "proxy-password"

		let serverCopy = Server(serverAddress: "irc.example.test")
		config.serverList = [serverCopy]

		let channelCopy = ChannelConfig(channelName: "#swift")
		config.channelList = [channelCopy]

		let plain = config
		let unique = config.uniqueCopy()

		#expect(plain.connectionName == "SwiftNet")
		#expect(plain.nicknamePassword == "nick-password")
		#expect(plain.proxyPassword == "proxy-password")
		#expect(plain.uniqueIdentifier == config.uniqueIdentifier)
		#expect(unique.nicknamePassword == "nick-password")
		#expect(unique.uniqueIdentifier != config.uniqueIdentifier)
		#expect(unique.serverList.first?.uniqueIdentifier != serverCopy.uniqueIdentifier)
		#expect(unique.channelList.first?.uniqueIdentifier != channelCopy.uniqueIdentifier)
	}

	@Test("Legacy keys migrate without overwriting an explicit modern cipher setting")
	func legacyKeysMigrateWithoutOverwritingExplicitModernCipherSetting() throws {
		let config = try decode([
			"connectOnLaunch": true,
			"connectOnDisconnect": true,
			"disconnectOnSleepMode": false,
			"identityNickname": "legacy-nick",
			"identityUsername": "legacy-user",
			"connectionPrefersModernCiphers": false,
			"serverList": [["serverAddress": "irc.example.test"]],
		])

		#expect(config.autoConnect)
		#expect(config.autoReconnect)
		#expect(config.autoSleepModeDisconnect == false)
		#expect(config.nickname == "legacy-nick")
		#expect(config.username == "legacy-user")
		#expect(config.cipherSuites == .none)
		#expect((config.dictionaryValue["dictionaryVersion"] as? NSNumber)?.uintValue == 710)
	}
}
