import CocoaExtensions
import Foundation
@testable import Glasstual
import Testing

@MainActor
@Suite("Server configuration persistence")
struct ServerConfigPersistenceTests {
	/// The fixtures below are written the way a stored plist reads, so they are
	/// narrowed here rather than spelled as typed values one entry at a time.
	private func decode(_ dictionary: [String: Any]) throws -> ServerConfig {
		try decode(#require([String: PropertyListValue](propertyList: dictionary)))
	}

	private func decode(_ dictionary: [String: PropertyListValue]) throws -> ServerConfig {
		try #require(PropertyListModel.decode(ServerConfig.self, from: dictionary))
	}

	@Test("A configuration with nothing but a version carries the documented defaults")
	func defaultsMatchPersistedConfigurationContract() throws {
		let config = try decode(["dictionaryVersion": 1])

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
			"dictionaryVersion": 1,
			"connectionName": "Libera Chat",
			"nickname": "swift-user",
			"autoConnect": true,
			"addressType": ConnectionAddressKind.v6.rawValue,
			"proxyType": ConnectionProxyKind.socks5.rawValue,
			"proxyAddress": "proxy.example.test",
			"proxyPort": 1081,
			"serverList": [[
				"serverAddress": "irc.example.test",
				"serverPort": 6697,
				"prefersSecuredConnection": true,
			]],
			"conversationList": [[
				"name": "#swift",
				"type": ConversationKind.channel.rawValue,
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
		#expect(restored.conversationList.first?.name == "#swift")
	}

	@Test("A nested channel survives decoding")
	func nestedChannelSurvivesDecoding() throws {
		let config = try decode([
			"dictionaryVersion": 1,
			"conversationList": [[
				"name": "#runtime-dispatch",
				"type": ConversationKind.channel.rawValue,
			]],
		])

		let channel = try #require(config.conversationList.first)

		#expect(channel.name == "#runtime-dispatch")
		#expect(channel.type == .channel)
	}

	/// A duplicate mints new identifiers all the way down, and carries the
	/// secrets across so the identifier change does not lose them.
	@Test("A unique copy renames every identity and keeps the secrets")
	func uniqueCopyRenamesEveryIdentityAndKeepsSecrets() {
		var config = ServerConfig(connectionName: "SwiftNet")
		config.nicknamePassword = "nick-password"
		config.proxyPassword = "proxy-password"

		let serverCopy = ServerEndpoint(serverAddress: "irc.example.test")
		config.serverList = [serverCopy]

		let channelCopy = ConversationConfig(name: "#swift")
		config.conversationList = [channelCopy]

		let unique = config.uniqueCopy()

		#expect(unique.connectionName == "SwiftNet")
		#expect(unique.nicknamePassword == "nick-password")
		#expect(unique.proxyPassword == "proxy-password")
		#expect(unique.uniqueIdentifier != config.uniqueIdentifier)
		#expect(unique.serverList.first?.uniqueIdentifier != serverCopy.uniqueIdentifier)
		#expect(unique.conversationList.first?.uniqueIdentifier != channelCopy.uniqueIdentifier)
	}
}
