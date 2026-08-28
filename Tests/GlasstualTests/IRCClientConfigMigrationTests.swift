import CocoaExtensions
@testable import Glasstual
import GlasstualPluginKit
import XCTest

@MainActor
final class IRCClientConfigMigrationTests: XCTestCase {
	private func decode(_ dictionary: [String: Any]) throws -> ClientConfig {
		try XCTUnwrap(PropertyListModel.decode(ClientConfig.self, from: dictionary))
	}

	func testDefaultsMatchPersistedConfigurationContract() throws {
		let config = try decode(["dictionaryVersion": 710])

		XCTAssertFalse(config.autoConnect)
		XCTAssertFalse(config.autoReconnect)
		XCTAssertTrue(config.autoSleepModeDisconnect)
		XCTAssertTrue(config.performPongTimer)
		XCTAssertTrue(config.sendWhoCommandRequestsToChannels)
		XCTAssertTrue(config.validateServerCertificateChain)
		XCTAssertEqual(config.addressType, .default)
		XCTAssertEqual(config.proxyType, .automatic)
		XCTAssertEqual(config.proxyPort, 1080)
		XCTAssertEqual(config.floodControlDelayTimerInterval, 2)
		XCTAssertEqual(config.floodControlMaximumMessages, 6)
		XCTAssertFalse(config.connectionName.isEmpty)
		XCTAssertFalse(config.uniqueIdentifier.isEmpty)
	}

	func testDictionaryRoundTripPreservesCurrentSchema() throws {
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

		XCTAssertEqual(restored.connectionName, "Libera Chat")
		XCTAssertEqual(restored.nickname, "swift-user")
		XCTAssertTrue(restored.autoConnect)
		XCTAssertEqual(restored.addressType, .v6)
		XCTAssertEqual(restored.proxyType, .socks5)
		XCTAssertEqual(restored.proxyAddress, "proxy.example.test")
		XCTAssertEqual(restored.proxyPort, 1081)
		XCTAssertEqual(restored.serverList.first?.serverAddress, "irc.example.test")
		XCTAssertEqual(restored.serverList.first?.serverPort, 6697)
		XCTAssertEqual(restored.channelList.first?.channelName, "#swift")
	}

	func testNestedChannelSurvivesDecodingAndCopying() throws {
		let config = try decode([
			"dictionaryVersion": 710,
			"channelList": [[
				"channelName": "#runtime-dispatch",
				"channelType": ChannelType.channel.rawValue,
			]],
		])

		let copy = config
		let channel = try XCTUnwrap(copy.channelList.first)

		XCTAssertEqual(channel.channelName, "#runtime-dispatch")
		XCTAssertEqual(channel.type, .channel)
	}

	/// A duplicate mints new identifiers all the way down, and carries the
	/// secrets across so the identifier change does not lose them.
	func testUniqueCopyRenamesEveryIdentityAndKeepsSecrets() {
		var config = ClientConfig(connectionName: "SwiftNet")
		config.nicknamePassword = "nick-password"
		config.proxyPassword = "proxy-password"

		let serverCopy = Server(serverAddress: "irc.example.test")
		config.serverList = [serverCopy]

		let channelCopy = ChannelConfig(channelName: "#swift")
		config.channelList = [channelCopy]

		let plain = config
		let unique = config.uniqueCopy()

		XCTAssertEqual(plain.connectionName, "SwiftNet")
		XCTAssertEqual(plain.nicknamePassword, "nick-password")
		XCTAssertEqual(plain.proxyPassword, "proxy-password")
		XCTAssertEqual(plain.uniqueIdentifier, config.uniqueIdentifier)
		XCTAssertEqual(unique.nicknamePassword, "nick-password")
		XCTAssertNotEqual(unique.uniqueIdentifier, config.uniqueIdentifier)
		XCTAssertNotEqual(unique.serverList.first?.uniqueIdentifier, serverCopy.uniqueIdentifier)
		XCTAssertNotEqual(unique.channelList.first?.uniqueIdentifier, channelCopy.uniqueIdentifier)
	}

	func testLegacyKeysMigrateWithoutOverwritingExplicitModernCipherSetting() throws {
		let config = try decode([
			"connectOnLaunch": true,
			"connectOnDisconnect": true,
			"disconnectOnSleepMode": false,
			"identityNickname": "legacy-nick",
			"identityUsername": "legacy-user",
			"connectionPrefersModernCiphers": false,
			"serverList": [["serverAddress": "irc.example.test"]],
		])

		XCTAssertTrue(config.autoConnect)
		XCTAssertTrue(config.autoReconnect)
		XCTAssertFalse(config.autoSleepModeDisconnect)
		XCTAssertEqual(config.nickname, "legacy-nick")
		XCTAssertEqual(config.username, "legacy-user")
		XCTAssertEqual(config.cipherSuites, .none)
		XCTAssertEqual((config.dictionaryValue["dictionaryVersion"] as? NSNumber)?.uintValue, 710)
	}
}
