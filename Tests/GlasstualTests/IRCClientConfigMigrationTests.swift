import CocoaExtensions
@testable import Glasstual
import GlasstualPluginKit
import XCTest

@MainActor
final class IRCClientConfigMigrationTests: XCTestCase {
	func testDefaultsMatchPersistedConfigurationContract() {
		let config = ClientConfig(dictionary: ["dictionaryVersion": 710])

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
		XCTAssertFalse(config.nickname.isEmpty)
		XCTAssertFalse(config.uniqueIdentifier.isEmpty)
	}

	func testDictionaryRoundTripPreservesCurrentSchema() {
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

		let config = ClientConfig(dictionary: input)
		let restored = ClientConfig(dictionary: config.dictionaryValue)

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

	func testClientConfigConstructsAndCopiesNestedChannelThroughPortableDictionaryBase() throws {
		let config = ClientConfig(dictionary: [
			"dictionaryVersion": 710,
			"channelList": [[
				"channelName": "#runtime-dispatch",
				"channelType": ChannelType.channel.rawValue,
			]],
		])

		let mutableCopy = try XCTUnwrap(config.mutableCopy() as? MutableClientConfig)
		let channel = try XCTUnwrap(mutableCopy.channelList.first)

		XCTAssertEqual(channel.channelName, "#runtime-dispatch")
		XCTAssertEqual(channel.type, .channel)
		XCTAssertTrue(mutableCopy.initializedAsCopy)
	}

	func testMutableAndUniqueCopiesPreservePrivateValuesAndNestedIdentity() throws {
		let config = MutableClientConfig()
		config.connectionName = "SwiftNet"
		config.nicknamePassword = "nick-password"
		config.proxyPassword = "proxy-password"

		let server = MutableServer()
		server.serverAddress = "irc.example.test"
		let serverCopy = try XCTUnwrap(server.copy() as? Server)
		config.serverList = [serverCopy]

		let channel = MutableChannelConfig()
		channel.channelName = "#swift"
		let channelCopy = try XCTUnwrap(channel.copy() as? ChannelConfig)
		config.channelList = [channelCopy]

		let immutable = try XCTUnwrap(config.copy() as? ClientConfig)
		let unique = try XCTUnwrap(config.uniqueCopyMutable() as? MutableClientConfig)

		XCTAssertEqual(immutable.connectionName, "SwiftNet")
		XCTAssertEqual(immutable.nicknamePassword, "nick-password")
		XCTAssertEqual(immutable.proxyPassword, "proxy-password")
		XCTAssertEqual(immutable.uniqueIdentifier, config.uniqueIdentifier)
		XCTAssertEqual(unique.nicknamePassword, "nick-password")
		XCTAssertNotEqual(unique.uniqueIdentifier, config.uniqueIdentifier)
		XCTAssertNotEqual(unique.serverList.first?.uniqueIdentifier, serverCopy.uniqueIdentifier)
		XCTAssertNotEqual(unique.channelList.first?.uniqueIdentifier, channelCopy.uniqueIdentifier)
	}

	func testLegacyKeysMigrateWithoutOverwritingExplicitModernCipherSetting() {
		let config = ClientConfig(dictionary: [
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
