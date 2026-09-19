// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation
@testable import Glasstual
import Testing

/** The session list lives in `UserDefaults` as property-list dictionaries, so a
 stored configuration has to decode into the values it names and encode back to
 exactly the keys it was read from. */
@Suite("Server configuration property-list round trip")
@MainActor
struct ServerConfigCodableTests {
	/** The Settings stepper offers `0 ... 60` seconds and the import check
	 refuses anything else, which leaves a hand-edited session list as the one way
	 something else reaches the property. Every later use reads it as seconds:
	 the sheet's label narrows it to an `Int`, and the autojoin turns it into a
	 `Duration`. */
	@Test(
		"An autojoin delay a plist edit can carry is bounded where the configuration is read",
		arguments: [
			PropertyListValue.double(.nan),
			.double(.infinity),
			.double(-.infinity),
			.double(1e308),
			.double(-5),
			.double(600),
		]
	)
	func autojoinDelayIsBoundedOnDecode(_ stored: PropertyListValue) throws {
		var fixture = Self.storedFixture
		fixture["autojoinDelayAfterConnectCommands"] = stored

		let config = try #require(PropertyListModel.decode(ServerConfig.self, from: fixture))
		let delay = config.autojoinDelayAfterConnectCommands

		#expect(delay >= 0)
		#expect(delay <= ServerConfigDefaults.maximumAutojoinConnectCommandDelay)
		#expect(Int(exactly: delay) != nil)
	}

	@Test("An absent SASL choice leaves it on, and an explicit off survives encoding")
	func saslChoicePersistence() throws {
		var config = try #require(PropertyListModel.decode(ServerConfig.self, from: Self.storedFixture))
		#expect(config.usesSASL)
		config.usesSASL = false
		config.nicknamePassword = "secret"
		let encoded = PropertyListModel.encode(config)
		let restored = try #require(PropertyListModel.decode(ServerConfig.self, from: encoded))
		#expect(restored.usesSASL == false)
		#expect(encoded["nicknamePassword"] == nil)
		#expect(config.pendingNicknamePassword == .set("secret"))
	}

	/// One stored configuration with an entry in each owned list.
	private static let storedFixture: [String: PropertyListValue] = [
		"dictionaryVersion": 1,
		"uniqueIdentifier": "8B2F4C1A-0000-4000-8000-00000000000A",
		"connectionName": "Libera Chat",
		"nickname": "swift-user",
		"awayNickname": "swift-user|away",
		"username": "swiftuser",
		"realName": "Swift User",
		"alternateNicknames": ["swift-user_"],
		"loginCommands": ["/msg NickServ identify"],
		"autoConnect": true,
		"serverList": [[
			"uniqueIdentifier": "8B2F4C1A-0000-4000-8000-00000000000B",
			"serverAddress": "irc.libera.chat",
			"serverPort": 6697,
			"prefersSecuredConnection": true,
		]],
		"conversationList": [[
			"name": "#swift",
			"uniqueIdentifier": "8B2F4C1A-0000-4000-8000-00000000000C",
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

	@Test("A stored session list entry re-encodes to the same dictionary")
	func storedFixtureRoundTrips() throws {
		let config = try #require(PropertyListModel.decode(ServerConfig.self, from: Self.storedFixture))

		#expect(
			PropertyListModel.encode(config) == Self.storedFixture
		)
	}

	@Test("Every nested list decodes into its own model")
	func storedFixtureDecodesNestedLists() throws {
		let config = try #require(PropertyListModel.decode(ServerConfig.self, from: Self.storedFixture))

		#expect(config.serverList.first?.serverAddress == "irc.libera.chat")
		#expect(config.conversationList.first?.name == "#swift")
		#expect(config.highlightList.first?.matchKeyword == "release")
		#expect(config.ignoreList.first?.hostmask == "spammer!*@example.test")
	}

	@Test("Neither password is part of the encoded value")
	func passwordsAreNeverEncoded() {
		var config = ServerConfig(connectionName: "Libera Chat")
		config.nicknamePassword = "nick-secret"
		config.proxyPassword = "proxy-secret"

		let encoded = PropertyListModel.encode(config)

		#expect(encoded["nicknamePassword"] == nil)
		#expect(encoded["proxyPassword"] == nil)
		#expect(encoded["proxyServerPassword"] == nil)
		#expect(config.pendingNicknamePassword == .set("nick-secret"))
	}

	/// Asking for IPv4 twice over is what the server-properties sheet warns
	/// about, and the warning is read off the stored pair.
	@Test("A configuration pinned to IPv4 twice over asks for the warning")
	func doublePinnedIPv4AsksForTheWarning() throws {
		let config = try #require(PropertyListModel.decode(ServerConfig.self, from: [
			"addressType": .integer(Int(ConnectionAddressKind.v4.rawValue)),
			"connectionPrefersIPv4": true,
		]))

		#expect(config.addressType == .v4)
		#expect(config.showConnectionPrefersIPv4Warning)
	}

	@Test("A malformed highlight condition is dropped rather than loaded")
	func malformedHighlightConditionsAreDropped() throws {
		let config = try #require(PropertyListModel.decode(ServerConfig.self, from: [
			"dictionaryVersion": 1,
			"highlightList": [
				["matchKeyword": "keep"],
				["matchIsExcluded": true],
			],
		]))

		#expect(config.highlightList.count == 1)
	}

	/// The encoder used to measure the outgoing burst against one default while
	/// the decoder filled a missing key from another, so the setting moved on
	/// every save. Both halves now read the same reference.
	@Test("A reduced flood-control burst survives a round trip")
	func reducedFloodControlSurvivesRoundTrip() throws {
		var config = ServerConfig(connectionName: "Libera Chat")
		config.floodControlMaximumMessages = 2

		let encoded = PropertyListModel.encode(config)
		let decoded = try #require(PropertyListModel.decode(ServerConfig.self, from: encoded))

		#expect(decoded.floodControlMaximumMessages == 2)
	}

	/// A setting sitting on its default stays out of the dictionary; one the
	/// user changed has to come back.
	@Test("The connect-command autojoin wait and its delay survive a round trip")
	func autojoinWaitForConnectCommandsSurvivesRoundTrip() throws {
		var config = ServerConfig(connectionName: "Libera Chat")
		let untouched = PropertyListModel.encode(config)

		#expect(untouched["autojoinWaitsForConnectCommands"] == nil)
		#expect(untouched["autojoinDelayAfterConnectCommands"] == nil)

		config.autojoinWaitsForConnectCommands = true
		config.autojoinDelayAfterConnectCommands = 12
		let encoded = PropertyListModel.encode(config)

		#expect(encoded["autojoinWaitsForConnectCommands"] == true)
		#expect(encoded["autojoinDelayAfterConnectCommands"] == 12.0)

		let decoded = try #require(PropertyListModel.decode(ServerConfig.self, from: encoded))

		#expect(decoded.autojoinWaitsForConnectCommands)
		#expect(decoded.autojoinDelayAfterConnectCommands == 12)
	}

	/// A configuration that never asked for the wait reads back with it switched
	/// off and the delay on its default.
	@Test("A dictionary without the keys leaves the wait off and the delay standard")
	func missingConnectCommandWaitKeyDefaultsToOff() throws {
		let config = try #require(PropertyListModel.decode(ServerConfig.self, from: [
			"dictionaryVersion": 1,
			"connectionName": "Libera Chat",
		]))

		#expect(config.autojoinWaitsForConnectCommands == false)
		#expect(config.autojoinDelayAfterConnectCommands == ServerConfigDefaults.autojoinConnectCommandDelay)
	}

	/** Encoding leaves out whatever a decoder would assume, so the two halves
	 have to assume the same things. A configuration on its defaults is the
	 case that proves it: whatever it writes is a key whose default the two
	 sides disagree about, and whatever it drops has to come back unchanged. */
	@Test("A configuration on its defaults writes only the always-written keys and survives the trip")
	func defaultConfigurationRoundTripsThroughTheKeysItWrites() throws {
		let config = ServerConfig(connectionName: "Libera Chat")
		let encoded = PropertyListModel.encode(config)

		/* The away nickname is seeded from a setting the machine running the
		 test may or may not have set, so its key is the one whose presence is
		 not fixed. */
		#expect(Set(encoded.keys).subtracting(["awayNickname"]) == [
			"dictionaryVersion",
			"uniqueIdentifier",
			// Seeded from a setting, so never left to a reader to assume.
			"nickname",
			"username",
			"realName",
			// An absent list and an empty list mean different things to an import.
			"loginCommands",
			// Named here rather than left on the untitled default.
			"connectionName",
		])

		let decoded = try #require(PropertyListModel.decode(ServerConfig.self, from: encoded))

		#expect(decoded == config)
	}

	/// A configuration left on the standard maximum keeps it: the key stays out
	/// of the dictionary and the decoder reads it back from the same reference.
	@Test("A configuration on the standard flood maximum keeps it")
	func standardFloodMaximumSurvivesRoundTrip() throws {
		let config = ServerConfig(connectionName: "Libera Chat")

		let encoded = PropertyListModel.encode(config)
		let decoded = try #require(PropertyListModel.decode(ServerConfig.self, from: encoded))

		#expect(encoded["floodControlMaximumMessages"] == nil)
		#expect(decoded.floodControlMaximumMessages == ServerConfigDefaults.floodMaximum)
	}

	/// A fresh session config reads its identity from the settings rather
	/// than starting blank, and the away nickname is the one field that stays
	/// empty until the person fills it in.
	@Test("A fresh session config takes its identity from the settings")
	func freshSessionConfigReadsIdentityFromSettings() {
		let serverConfig = ServerConfig()

		#expect(serverConfig.connectionName.isEmpty == false)
		#expect(serverConfig.nickname.isEmpty == false)
		#expect(serverConfig.conversationList.isEmpty)
		#expect(serverConfig.awayNickname == "")
	}
}
