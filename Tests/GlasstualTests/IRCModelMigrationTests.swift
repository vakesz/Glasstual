/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import AppKit
import CocoaExtensions
@testable import Glasstual
import GlasstualPluginKit
import XCTest

@MainActor
final class IRCModelMigrationTests: XCTestCase {
	func testConnectionInitialStateAndConfigIsolation() {
		let client = GLTTestClient()
		let sourceConfig = Glasstual.IRCConnectionConfigMutable()
		sourceConfig.serverAddress = "irc.example.test"

		let connection = Connection(config: sourceConfig, onClient: client)
		sourceConfig.serverAddress = "changed.example.test"

		XCTAssertTrue(connection.client === client)
		XCTAssertEqual(connection.config.serverAddress, "irc.example.test")
		XCTAssertFalse(connection.uniqueIdentifier.isEmpty)
		XCTAssertFalse(connection.isConnecting)
		XCTAssertFalse(connection.isConnected)
		XCTAssertFalse(connection.isDisconnecting)
		XCTAssertFalse(connection.isSecured)
		XCTAssertFalse(connection.isSending)
		XCTAssertFalse(connection.EOFReceived)
	}

	func testConnectionResetClearsTransientState() {
		let connection = Connection(config: Glasstual.IRCConnectionConfig(), onClient: GLTTestClient())

		connection.resetState()

		XCTAssertFalse(connection.isConnecting)
		XCTAssertFalse(connection.isConnected)
		XCTAssertFalse(connection.isConnectedWithClientSideCertificate)
		XCTAssertFalse(connection.isDisconnecting)
		XCTAssertFalse(connection.isSecured)
		XCTAssertFalse(connection.isSending)
		XCTAssertFalse(connection.EOFReceived)
		XCTAssertNil(connection.connectedAddress)
	}

	func testChannelConfigDefaultsAndLegacyKeys() {
		let defaults = ChannelConfig.seed(withName: "#general")

		XCTAssertTrue(defaults.autoJoin)
		XCTAssertTrue(defaults.pushNotifications)
		XCTAssertTrue(defaults.showTreeBadgeCount)
		XCTAssertEqual(defaults.type, .channel)
		XCTAssertEqual(defaults.channelName, "#general")
		XCTAssertFalse(defaults.uniqueIdentifier.isEmpty)

		let legacy = ChannelConfig(dictionary: [
			"channelName": "#legacy",
			"joinOnConnect": false,
			"ignoreJPQActivity": true,
			"enableNotifications": false,
			"enableTreeBadgeCountDrawing": false,
		])

		XCTAssertFalse(legacy.autoJoin)
		XCTAssertTrue(legacy.ignoreGeneralEventMessages)
		XCTAssertFalse(legacy.pushNotifications)
		XCTAssertFalse(legacy.showTreeBadgeCount)
	}

	func testChannelConfigMutableAndUniqueCopiesPreserveValues() throws {
		let mutable = MutableChannelConfig()
		mutable.channelName = "#swift"
		mutable.label = "Swift migration"
		mutable.defaultModes = "+nt"
		mutable.secretKey = "join-key"

		let copy = try XCTUnwrap(mutable.copy() as? ChannelConfig)
		let unique = try XCTUnwrap(mutable.uniqueCopyMutable() as? MutableChannelConfig)

		XCTAssertEqual(copy.channelName, "#swift")
		XCTAssertEqual(copy.label, "Swift migration")
		XCTAssertEqual(copy.defaultModes, "+nt")
		XCTAssertEqual(copy.secretKey, "join-key")
		XCTAssertEqual(copy.uniqueIdentifier, mutable.uniqueIdentifier)
		XCTAssertEqual(unique.channelName, "#swift")
		XCTAssertEqual(unique.secretKey, "join-key")
		XCTAssertNotEqual(unique.uniqueIdentifier, mutable.uniqueIdentifier)
	}

	func testChannelConfigNotificationOverridesUseThreeStateSemantics() {
		let config = MutableChannelConfig()
		let event = TXNotificationType.highlight

		XCTAssertEqual(config.notificationEnabled(forEvent: event), .mixed)

		config.setNotificationEnabled(.on, forEvent: event)
		XCTAssertEqual(config.notificationEnabled(forEvent: event), .on)

		config.setNotificationEnabled(.off, forEvent: event)
		XCTAssertEqual(config.notificationEnabled(forEvent: event), .off)

		config.setNotificationEnabled(.mixed, forEvent: event)
		XCTAssertEqual(config.notificationEnabled(forEvent: event), .mixed)
	}

	func testHighlightMatchConditionRoundTripsDictionaryAndDefaults() throws {
		let condition = try XCTUnwrap(PropertyListModel.decode(HighlightMatchCondition.self, from: [
			"matchKeyword": "alert",
			"matchChannelID": "chan-1",
			"matchIsExcluded": true,
		]))

		XCTAssertEqual(condition.matchKeyword, "alert")
		XCTAssertEqual(condition.matchChannelId, "chan-1")
		XCTAssertTrue(condition.matchIsExcluded)
		XCTAssertFalse(condition.uniqueIdentifier.isEmpty)

		let dictionary = PropertyListModel.encode(condition)

		XCTAssertEqual(dictionary["matchKeyword"] as? String, "alert")
		XCTAssertEqual(dictionary["matchChannelID"] as? String, "chan-1")
		XCTAssertEqual(dictionary["matchIsExcluded"] as? Bool, true)
		XCTAssertEqual(dictionary["uniqueIdentifier"] as? String, condition.uniqueIdentifier)
	}

	func testHighlightMatchConditionEditsAndUniqueCopyAreIndependent() {
		let original = HighlightMatchCondition(matchKeyword: "ping")
		var edited = original
		edited.matchKeyword = "pong"
		edited.matchIsExcluded = true

		XCTAssertEqual(original.matchKeyword, "ping")
		XCTAssertFalse(original.matchIsExcluded)
		XCTAssertEqual(edited.matchKeyword, "pong")
		XCTAssertTrue(edited.matchIsExcluded)

		let unique = original.uniqueCopy()

		XCTAssertEqual(unique.matchKeyword, "ping")
		XCTAssertNotEqual(unique.uniqueIdentifier, original.uniqueIdentifier)
	}

	func testServerDefaultsAndDictionaryRoundTrip() throws {
		let server = try XCTUnwrap(PropertyListModel.decode(Server.self, from: [
			"serverAddress": "irc.example.test",
			"serverPort": 6697,
			"prefersSecuredConnection": true,
		]))

		XCTAssertEqual(server.serverAddress, "irc.example.test")
		XCTAssertEqual(server.serverPort, 6697)
		XCTAssertTrue(server.prefersSecuredConnection)
		XCTAssertFalse(server.uniqueIdentifier.isEmpty)

		let empty = Server()

		XCTAssertEqual(empty.serverPort, 6667)
		XCTAssertEqual(empty.serverAddress, "")
	}

	func testServerPasswordAndUniqueCopy() {
		var server = Server(serverAddress: "chat.example.test", serverPort: 6667)
		server.serverPassword = "s3cret"

		XCTAssertEqual(server.serverPassword, "s3cret")

		let unique = server.uniqueCopy()

		XCTAssertEqual(unique.serverAddress, "chat.example.test")
		XCTAssertNotEqual(unique.uniqueIdentifier, server.uniqueIdentifier)
		XCTAssertEqual(unique.serverPassword, "s3cret")
	}

	func testHighlightLogEntryStoresLineClientAndChannel() {
		let line = MutableLogLine()
		line.messageBody = "hello world"
		line.nickname = "alice"
		line.lineType = .privateMessage
		line.receivedAt = Date(timeIntervalSince1970: 1_700_000_000)

		let entry = HighlightLogEntry(lineLogged: line, clientId: "client-a", channelId: "channel-b")

		XCTAssertEqual(entry.clientId, "client-a")
		XCTAssertEqual(entry.channelId, "channel-b")
		XCTAssertEqual(entry.lineNumber, line.uniqueIdentifier)
		XCTAssertEqual(entry.timeLogged, line.receivedAt)
		XCTAssertGreaterThan(entry.renderedMessage.length, 0)
		XCTAssertFalse(entry.timeLoggedFormatted.isEmpty)
	}

	func testUserPersistentStoreHoldsRelationsAndTimerSlot() {
		let store = UserPersistentStore()
		let relations = UserRelations()
		store.relations = relations
		store.presentAwayMessageFor301LastEvent = 12.5

		XCTAssertTrue(store.relations === relations)
		XCTAssertEqual(store.presentAwayMessageFor301LastEvent, 12.5)
		XCTAssertNil(store.removeUserTimer)
	}
}
