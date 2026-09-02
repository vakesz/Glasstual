/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import CocoaExtensions
import Foundation
@testable import Glasstual
import GlasstualPluginKit
import Testing

/** The client list lives in `UserDefaults` as property-list dictionaries, so a
 configuration written by the previous release has to decode into the same
 values and encode back to the same keys. */
@Suite("Client configuration property-list round trip")
@MainActor
struct IRCClientConfigCodableTests {
	/// Captured from the class-based `IRCClientConfig.dictionaryValue`, with
	/// one entry in each owned list.
	private static let worldFixture: [String: PropertyListValue] = [
		"dictionaryVersion": 710,
		"uniqueIdentifier": "8B2F4C1A-0000-4000-8000-00000000000A",
		"connectionName": "Libera Chat",
		"nickname": "swift-user",
		"awayNickname": "swift-user|away",
		"username": "swiftuser",
		"realName": "Swift User",
		"alternateNicknames": ["swift-user_"],
		"onConnectCommands": ["/msg NickServ identify"],
		"autoConnect": true,
		"connectionPrefersIPv4": false,
		"connectionPrefersModernCiphers": true,
		"serverAddress": "irc.libera.chat",
		"serverPort": 6697,
		"prefersSecuredConnection": true,
		"serverList": [[
			"uniqueIdentifier": "8B2F4C1A-0000-4000-8000-00000000000B",
			"serverAddress": "irc.libera.chat",
			"serverPort": 6697,
			"prefersSecuredConnection": true,
		]],
		"channelList": [[
			"channelName": "#swift",
			"uniqueIdentifier": "8B2F4C1A-0000-4000-8000-00000000000C",
			"notifications": .dictionary([:]),
		]],
		"highlightList": [[
			"matchKeyword": "release",
			"uniqueIdentifier": "8B2F4C1A-0000-4000-8000-00000000000D",
			"matchIsExcluded": false,
		]],
		"ignoreList": [[
			"hostmask": "spammer!*@example.test",
			"uniqueIdentifier": "8B2F4C1A-0000-4000-8000-00000000000E",
			"ignorePublicMessages": true,
		]],
	]

	@Test("A stored client list entry re-encodes to the same dictionary")
	func worldFixtureRoundTrips() throws {
		let config = try #require(PropertyListModel.decode(ClientConfig.self, from: Self.worldFixture))

		#expect(
			PropertyListModel.encode(config) == Self.worldFixture
		)
	}

	@Test("Every nested list decodes into its own model")
	func worldFixtureDecodesNestedLists() throws {
		let config = try #require(PropertyListModel.decode(ClientConfig.self, from: Self.worldFixture))

		#expect(config.serverList.first?.serverAddress == "irc.libera.chat")
		#expect(config.channelList.first?.channelName == "#swift")
		#expect(config.highlightList.first?.matchKeyword == "release")
		#expect(config.ignoreList.first?.hostmask == "spammer!*@example.test")
	}

	@Test("Neither password is part of the encoded value")
	func passwordsAreNeverEncoded() {
		var config = ClientConfig(connectionName: "Libera Chat")
		config.nicknamePassword = "nick-secret"
		config.proxyPassword = "proxy-secret"

		let encoded = PropertyListModel.encode(config)

		#expect(encoded["nicknamePassword"] == nil)
		#expect(encoded["proxyPassword"] == nil)
		#expect(encoded["proxyServerPassword"] == nil)
		#expect(config.pendingNicknamePassword == .set("nick-secret"))
	}

	/// The class this replaced assigned every optional unconditionally, so a
	/// merge from a configuration that left one out wiped it.
	@Test("Merging keeps an optional the second configuration does not carry")
	func mergingDoesNotWipeAbsentOptionals() {
		var first = ClientConfig(connectionName: "Libera Chat")
		first.awayNickname = "swift-user|away"
		first.ctcpVersionReply = "Glasstual"
		first.proxyAddress = "proxy.example.test"
		first.saslMechanismPreference = "PLAIN"

		var second = first
		second.awayNickname = nil
		second.ctcpVersionReply = nil
		second.proxyAddress = nil
		second.saslMechanismPreference = nil
		second.connectionName = "Libera"

		let merged = ClientConfig.merging(first, with: second)

		#expect(merged.connectionName == "Libera")
		#expect(merged.awayNickname == "swift-user|away")
		#expect(merged.ctcpVersionReply == "Glasstual")
		#expect(merged.proxyAddress == "proxy.example.test")
		#expect(merged.saslMechanismPreference == "PLAIN")
	}

	@Test("A version 0 dictionary moves its flood-control settings across")
	func versionZeroFloodControl() throws {
		let config = try #require(PropertyListModel.decode(ClientConfig.self, from: [
			"floodControl": [
				"serviceEnabled": true,
				"delayTimerInterval": 5,
				"maximumMessageCount": 3,
			],
		]))

		#expect(config.floodControlDelayTimerInterval == 5)
		#expect(config.floodControlMaximumMessages == 3)
	}

	@Test("Turning version 0 flood control off means the loosest settings")
	func versionZeroFloodControlDisabled() throws {
		let config = try #require(PropertyListModel.decode(ClientConfig.self, from: [
			"isOutgoingFloodControlEnabled": false,
		]))

		#expect(config.floodControlDelayTimerInterval == 1)
		#expect(config.floodControlMaximumMessages == 60)
	}

	@Test("A version 0 IPv4 preference becomes the IPv4 address type")
	func versionZeroAddressType() throws {
		let config = try #require(PropertyListModel.decode(ClientConfig.self, from: [
			"connectionPrefersIPv4": true,
		]))

		#expect(config.addressType == .v4)
		#expect(config.showConnectionPrefersIPv4Warning)
	}

	@Test("A malformed highlight condition is dropped rather than loaded")
	func malformedHighlightConditionsAreDropped() throws {
		let config = try #require(PropertyListModel.decode(ClientConfig.self, from: [
			"dictionaryVersion": 710,
			"highlightList": [
				["matchKeyword": "keep"],
				["matchIsExcluded": true],
			],
		]))

		#expect(config.highlightList.count == 1)
	}

	/// The encoder used to measure the outgoing burst against the reduced
	/// default a rate-limited network gets, while the decoder filled a missing
	/// key from the standard one, so the setting tripled on every save.
	@Test("A rate-limited network keeps its reduced flood control across a round trip")
	func rateLimitedFloodControlSurvivesRoundTrip() throws {
		var config = ClientConfig(connectionName: "freenode")
		config.serverList = [Server(serverAddress: "chat.freenode.net")]
		config.floodControlMaximumMessages = 2

		let encoded = PropertyListModel.encode(config)
		let decoded = try #require(PropertyListModel.decode(ClientConfig.self, from: encoded))

		#expect(decoded.floodControlMaximumMessages == 2)
	}

	/// A setting sitting on its default stays out of the dictionary; one the
	/// user changed has to come back.
	@Test("The connect-command autojoin wait and its delay survive a round trip")
	func autojoinWaitForConnectCommandsSurvivesRoundTrip() throws {
		var config = ClientConfig(connectionName: "Libera Chat")
		let untouched = PropertyListModel.encode(config)

		#expect(untouched["autojoinWaitsForConnectCommands"] == nil)
		#expect(untouched["autojoinDelayAfterConnectCommands"] == nil)

		config.autojoinWaitsForConnectCommands = true
		config.autojoinDelayAfterConnectCommands = 12
		let encoded = PropertyListModel.encode(config)

		#expect(encoded["autojoinWaitsForConnectCommands"] == true)
		#expect(encoded["autojoinDelayAfterConnectCommands"] == 12.0)

		let decoded = try #require(PropertyListModel.decode(ClientConfig.self, from: encoded))

		#expect(decoded.autojoinWaitsForConnectCommands)
		#expect(decoded.autojoinDelayAfterConnectCommands == 12)
	}

	/// A configuration written before the option existed reads back with the
	/// wait switched off and the delay on its default.
	@Test("A dictionary without the keys leaves the wait off and the delay standard")
	func missingConnectCommandWaitKeyDefaultsToOff() throws {
		let config = try #require(PropertyListModel.decode(ClientConfig.self, from: [
			"dictionaryVersion": 710,
			"connectionName": "Libera Chat",
		]))

		#expect(config.autojoinWaitsForConnectCommands == false)
		#expect(config.autojoinDelayAfterConnectCommands == ClientConfigDefaults.autojoinConnectCommandDelay)
	}

	/// The same configuration left on the standard maximum has to keep that
	/// too, rather than being pulled down to the reduced default on load.
	@Test("A rate-limited network keeps a standard flood maximum the user chose")
	func rateLimitedFloodControlKeepsStandardMaximum() throws {
		var config = ClientConfig(connectionName: "freenode")
		config.serverList = [Server(serverAddress: "chat.freenode.net")]

		let encoded = PropertyListModel.encode(config)
		let decoded = try #require(PropertyListModel.decode(ClientConfig.self, from: encoded))

		#expect(decoded.floodControlMaximumMessages == 6)
	}
}
