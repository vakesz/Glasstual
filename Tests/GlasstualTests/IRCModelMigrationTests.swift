/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import AppKit
import CocoaExtensions
@testable import Glasstual
import GlasstualPluginKit
import Testing

@MainActor
@Suite("IRC model migration")
struct IRCModelMigrationTests {
	@Test("A connection copies the config it was made with and starts idle")
	func connectionInitialStateAndConfigIsolation() {
		let client = GLTTestClient()
		var sourceConfig = Glasstual.IRCConnectionConfig()
		sourceConfig.serverAddress = "irc.example.test"

		let connection = Connection(config: sourceConfig, onClient: client)
		sourceConfig.serverAddress = "changed.example.test"

		#expect(connection.client === client)
		#expect(connection.config.serverAddress == "irc.example.test")
		#expect(connection.uniqueIdentifier.isEmpty == false)
		#expect(connection.isConnecting == false)
		#expect(connection.isConnected == false)
		#expect(connection.isDisconnecting == false)
		#expect(connection.isSecured == false)
		#expect(connection.isSending == false)
		#expect(connection.EOFReceived == false)
	}

	@Test("Resetting a connection clears every transient flag and the connected address")
	func connectionResetClearsTransientState() {
		let connection = Connection(config: Glasstual.IRCConnectionConfig(), onClient: GLTTestClient())

		connection.resetState()

		#expect(connection.isConnecting == false)
		#expect(connection.isConnected == false)
		#expect(connection.isConnectedWithClientSideCertificate == false)
		#expect(connection.isDisconnecting == false)
		#expect(connection.isSecured == false)
		#expect(connection.isSending == false)
		#expect(connection.EOFReceived == false)
		#expect(connection.connectedAddress == nil)
	}

	@Test("A seeded channel config takes the declared defaults, and the legacy keys still decode")
	func channelConfigDefaultsAndLegacyKeys() throws {
		let defaults = ChannelConfig.seed(withName: "#general")

		#expect(defaults.autoJoin)
		#expect(defaults.pushNotifications)
		#expect(defaults.showTreeBadgeCount)
		#expect(defaults.type == .channel)
		#expect(defaults.channelName == "#general")
		#expect(defaults.uniqueIdentifier.isEmpty == false)

		let legacy = try #require(PropertyListModel.decode(ChannelConfig.self, from: [
			"channelName": "#legacy",
			"joinOnConnect": false,
			"ignoreJPQActivity": true,
			"enableNotifications": false,
			"enableTreeBadgeCountDrawing": false,
		]))

		#expect(legacy.autoJoin == false)
		#expect(legacy.ignoreGeneralEventMessages)
		#expect(legacy.pushNotifications == false)
		#expect(legacy.showTreeBadgeCount == false)
	}

	@Test("A plain copy keeps the identifier while a unique copy takes a new one")
	func channelConfigCopiesAndUniqueCopiesPreserveValues() {
		var config = ChannelConfig(channelName: "#swift")
		config.label = "Swift migration"
		config.defaultModes = "+nt"
		config.secretKey = "join-key"

		let copy = config
		let unique = config.uniqueCopy()

		#expect(copy.channelName == "#swift")
		#expect(copy.label == "Swift migration")
		#expect(copy.defaultModes == "+nt")
		#expect(copy.secretKey == "join-key")
		#expect(copy.uniqueIdentifier == config.uniqueIdentifier)
		#expect(unique.channelName == "#swift")
		#expect(unique.secretKey == "join-key")
		#expect(unique.uniqueIdentifier != config.uniqueIdentifier)
	}

	@Test("A per-channel notification override is three-state, not a boolean")
	func channelConfigNotificationOverridesUseThreeStateSemantics() {
		var config = ChannelConfig()
		let event = TXNotificationType.highlight

		#expect(config.notificationEnabled(forEvent: event) == .mixed)

		config.setNotificationEnabled(.on, forEvent: event)
		#expect(config.notificationEnabled(forEvent: event) == .on)

		config.setNotificationEnabled(.off, forEvent: event)
		#expect(config.notificationEnabled(forEvent: event) == .off)

		config.setNotificationEnabled(.mixed, forEvent: event)
		#expect(config.notificationEnabled(forEvent: event) == .mixed)
	}

	@Test("A highlight condition decodes the legacy channel key and encodes it back")
	func highlightMatchConditionRoundTripsDictionaryAndDefaults() throws {
		let condition = try #require(PropertyListModel.decode(HighlightMatchCondition.self, from: [
			"matchKeyword": "alert",
			"matchChannelID": "chan-1",
			"matchIsExcluded": true,
		]))

		#expect(condition.matchKeyword == "alert")
		#expect(condition.matchChannelId == "chan-1")
		#expect(condition.matchIsExcluded)
		#expect(condition.uniqueIdentifier.isEmpty == false)

		let dictionary = PropertyListModel.encode(condition)

		#expect(dictionary["matchKeyword"] as? String == "alert")
		#expect(dictionary["matchChannelID"] as? String == "chan-1")
		#expect(dictionary["matchIsExcluded"] as? Bool == true)
		#expect(dictionary["uniqueIdentifier"] as? String == condition.uniqueIdentifier)
	}

	@Test("Editing a highlight condition leaves the value it was copied from alone")
	func highlightMatchConditionEditsAndUniqueCopyAreIndependent() {
		let original = HighlightMatchCondition(matchKeyword: "ping")
		var edited = original
		edited.matchKeyword = "pong"
		edited.matchIsExcluded = true

		#expect(original.matchKeyword == "ping")
		#expect(original.matchIsExcluded == false)
		#expect(edited.matchKeyword == "pong")
		#expect(edited.matchIsExcluded)

		let unique = original.uniqueCopy()

		#expect(unique.matchKeyword == "ping")
		#expect(unique.uniqueIdentifier != original.uniqueIdentifier)
	}

	@Test("A server decodes the keys it was given and defaults the rest")
	func serverDefaultsAndDictionaryRoundTrip() throws {
		let server = try #require(PropertyListModel.decode(Server.self, from: [
			"serverAddress": "irc.example.test",
			"serverPort": 6697,
			"prefersSecuredConnection": true,
		]))

		#expect(server.serverAddress == "irc.example.test")
		#expect(server.serverPort == 6697)
		#expect(server.prefersSecuredConnection)
		#expect(server.uniqueIdentifier.isEmpty == false)

		let empty = Server()

		#expect(empty.serverPort == 6667)
		#expect(empty.serverAddress == "")
	}

	@Test("A unique copy of a server carries the password over under a new identifier")
	func serverPasswordAndUniqueCopy() {
		var server = Server(serverAddress: "chat.example.test", serverPort: 6667)
		server.serverPassword = "s3cret"

		#expect(server.serverPassword == "s3cret")

		let unique = server.uniqueCopy()

		#expect(unique.serverAddress == "chat.example.test")
		#expect(unique.uniqueIdentifier != server.uniqueIdentifier)
		#expect(unique.serverPassword == "s3cret")
	}

	@Test("A highlight log entry records the line it was made from and where it came from")
	func highlightLogEntryStoresLineClientAndChannel() {
		let line = LogLine()
		line.messageBody = "hello world"
		line.nickname = "alice"
		line.lineType = .privateMessage
		line.receivedAt = Date(timeIntervalSince1970: 1_700_000_000)

		let entry = HighlightLogEntry(lineLogged: line, clientId: "client-a", channelId: "channel-b")

		#expect(entry.clientId == "client-a")
		#expect(entry.channelId == "channel-b")
		#expect(entry.lineNumber == line.uniqueIdentifier)
		#expect(entry.timeLogged == line.receivedAt)
		#expect(entry.renderedMessage.length > 0)
		#expect(entry.timeLoggedFormatted.isEmpty == false)
	}

	@Test("A user's persistent store keeps its relations and leaves the timer slot empty")
	func userPersistentStoreHoldsRelationsAndTimerSlot() {
		let store = UserPersistentStore()
		let relations = UserRelations()
		store.relations = relations
		store.presentAwayMessageFor301LastEvent = 12.5

		#expect(store.relations === relations)
		#expect(store.presentAwayMessageFor301LastEvent == 12.5)
		#expect(store.removeUserTimer == nil)
	}
}
