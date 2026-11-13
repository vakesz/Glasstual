// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
import CocoaExtensions
@testable import Glasstual
import Testing

@MainActor
@Suite("IRC model persistence")
struct ModelPersistenceTests {
	@Test("A seeded channel config takes the declared defaults")
	func channelConfigDefaults() throws {
		let defaults = ConversationConfig.seed(withName: "#general")

		#expect(defaults.autoJoin)
		#expect(defaults.pushNotifications)
		#expect(defaults.showsUnreadCount)
		#expect(defaults.type == .channel)
		#expect(defaults.name == "#general")
		#expect(defaults.uniqueIdentifier.isEmpty == false)

		let stored = try #require(PropertyListModel.decode(ConversationConfig.self, from: [
			"name": "#stored",
			"autoJoin": false,
			"ignoreGeneralEventMessages": true,
			"pushNotifications": false,
			"showsUnreadCount": false,
		]))

		#expect(stored.autoJoin == false)
		#expect(stored.ignoreGeneralEventMessages)
		#expect(stored.pushNotifications == false)
		#expect(stored.showsUnreadCount == false)
	}

	/// Duplicating a channel is how "Add channel" seeds itself from the selected
	/// one, so everything but the identity has to come across.
	@Test("A unique copy takes a new identifier and keeps the rest of the channel")
	func channelConfigUniqueCopyTakesANewIdentifier() {
		var config = ConversationConfig(name: "#swift")
		config.label = "Swift migration"
		config.defaultModes = "+nt"
		config.secretKey = "join-key"

		let unique = config.uniqueCopy()

		#expect(unique.name == "#swift")
		#expect(unique.label == "Swift migration")
		#expect(unique.defaultModes == "+nt")
		#expect(unique.secretKey == "join-key")
		#expect(unique.uniqueIdentifier != config.uniqueIdentifier)
		#expect(unique.uniqueIdentifier.isEmpty == false)
	}

	@Test("A highlight condition decodes its channel key and encodes it back")
	func highlightMatchConditionRoundTripsDictionaryAndDefaults() throws {
		let condition = try #require(PropertyListModel.decode(HighlightMatchCondition.self, from: [
			"matchKeyword": "alert",
			"matchChannelId": "chan-1",
			"matchIsExcluded": true,
		]))

		#expect(condition.matchKeyword == "alert")
		#expect(condition.matchChannelId == "chan-1")
		#expect(condition.matchIsExcluded)
		#expect(condition.uniqueIdentifier.isEmpty == false)

		let dictionary = PropertyListModel.encode(condition)

		#expect(dictionary["matchKeyword"]?.string == "alert")
		#expect(dictionary["matchChannelId"]?.string == "chan-1")
		#expect(dictionary["matchIsExcluded"]?.boolean == true)
		#expect(dictionary["uniqueIdentifier"]?.string == condition.uniqueIdentifier)
	}

	@Test("A unique copy of a highlight condition takes a new identifier")
	func highlightMatchConditionUniqueCopyTakesANewIdentifier() {
		let original = HighlightMatchCondition(matchKeyword: "ping")

		let unique = original.uniqueCopy()

		#expect(unique.matchKeyword == "ping")
		#expect(unique.matchIsExcluded == original.matchIsExcluded)
		#expect(unique.uniqueIdentifier != original.uniqueIdentifier)
		#expect(unique.uniqueIdentifier.isEmpty == false)
	}

	@Test("A server decodes the keys it was given and defaults the rest")
	func serverDefaultsAndDictionaryRoundTrip() throws {
		let server = try #require(PropertyListModel.decode(ServerEndpoint.self, from: [
			"serverAddress": "irc.example.test",
			"serverPort": 6697,
			"prefersSecuredConnection": true,
		]))

		#expect(server.serverAddress == "irc.example.test")
		#expect(server.serverPort == 6697)
		#expect(server.prefersSecuredConnection)
		#expect(server.uniqueIdentifier.isEmpty == false)

		let empty = ServerEndpoint()

		#expect(empty.serverPort == 6667)
		#expect(empty.serverAddress == "")
	}

	@Test("A unique copy of a server carries the password over under a new identifier")
	func serverPasswordAndUniqueCopy() {
		var server = ServerEndpoint(serverAddress: "chat.example.test", serverPort: 6667)
		server.serverPassword = "s3cret"

		#expect(server.serverPassword == "s3cret")

		let unique = server.uniqueCopy()

		#expect(unique.serverAddress == "chat.example.test")
		#expect(unique.uniqueIdentifier != server.uniqueIdentifier)
		#expect(unique.serverPassword == "s3cret")
	}

	@Test("A highlight log entry records the line it was made from and where it came from")
	func highlightRecordStoresLineSessionAndChannel() {
		var line = ChatLine()
		line.messageBody = "hello world"
		line.nickname = "alice"
		line.lineType = .privateMessage
		line.receivedAt = Date(timeIntervalSince1970: 1_700_000_000)

		let entry = HighlightRecord(lineLogged: line, sessionId: "session-a", conversationId: "channel-b")

		#expect(entry.sessionId == "session-a")
		#expect(entry.conversationId == "channel-b")
		#expect(entry.lineNumber == line.uniqueIdentifier)
		#expect(entry.timeLogged == line.receivedAt)
	}
}
