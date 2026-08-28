/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import AppKit
import CocoaExtensions
import Foundation
@testable import Glasstual
import GlasstualPluginKit
import Testing

/// A channel writes only the settings that differ from the default, plus its
/// name, identifier and (for anything but a channel) its type — the shape
/// `ce_dictionaryByRemovingDefaults` produced.
@Suite("Channel configuration property-list round trip")
@MainActor
struct IRCChannelConfigCodableTests {
	@Test("A stored channel re-encodes unchanged")
	func roundTripsAStoredChannel() throws {
		// Captured from the class-based `ChannelConfig.dictionaryValue`.
		let fixture: [String: Any] = [
			"channelName": "#swift",
			"uniqueIdentifier": "8B2F4C1A-0000-4000-8000-000000000006",
			"notifications": [String: Any](),
			"autoJoin": false,
			"ignoreHighlights": true,
			"defaultTopic": "Swift talk",
		]

		let config = try #require(PropertyListModel.decode(ChannelConfig.self, from: fixture))

		#expect(config.type == .channel)
		#expect(config.autoJoin == false)
		#expect(config.ignoreHighlights)
		#expect(config.defaultTopic == "Swift talk")
		#expect(NSDictionary(dictionary: PropertyListModel.encode(config)) == NSDictionary(dictionary: fixture))
	}

	@Test("A stored query keeps only its name, identifier and type")
	func roundTripsAStoredQuery() throws {
		let fixture: [String: Any] = [
			"channelName": "alice",
			"uniqueIdentifier": "8B2F4C1A-0000-4000-8000-000000000007",
			"channelType": 1,
		]

		let config = try #require(PropertyListModel.decode(ChannelConfig.self, from: fixture))

		#expect(config.type == .privateMessage)
		#expect(NSDictionary(dictionary: PropertyListModel.encode(config)) == NSDictionary(dictionary: fixture))
	}

	@Test(
		"Each legacy spelling still sets the setting it was renamed to",
		arguments: [
			("joinOnConnect", "autoJoin"),
			("ignoreJPQActivity", "ignoreGeneralEventMessages"),
			("enableNotifications", "pushNotifications"),
			("enableTreeBadgeCountDrawing", "showTreeBadgeCount"),
		]
	)
	func legacyAliases(legacyKey: String, canonicalKey: String) throws {
		let onValue = legacyKey == "ignoreJPQActivity"
		let config = try #require(PropertyListModel.decode(ChannelConfig.self, from: [
			"channelName": "#swift",
			legacyKey: onValue,
		]))

		#expect(PropertyListModel.encode(config)[canonicalKey] as? Bool == onValue)
	}

	@Test("An absent optional stays nil rather than becoming an empty string")
	func absentOptionalsStayNil() throws {
		let config = try #require(PropertyListModel.decode(ChannelConfig.self, from: [
			"channelName": "#swift",
		]))

		#expect(config.label == nil)
		#expect(config.defaultModes == nil)
		#expect(config.defaultTopic == nil)
	}

	@Test("Notification overrides survive the round trip as sounds and flags")
	func notificationOverridesRoundTrip() throws {
		var config = ChannelConfig(channelName: "#swift")
		config.setSound("Glass", forEvent: .highlight)
		config.setNotificationEnabled(.off, forEvent: .highlight)

		let restored = try #require(
			PropertyListModel.decode(ChannelConfig.self, from: PropertyListModel.encode(config))
		)

		#expect(restored.sound(forEvent: .highlight) == "Glass")
		#expect(restored.notificationEnabled(forEvent: .highlight) == .off)
		#expect(restored.notificationEnabled(forEvent: .channelMessage) == .mixed)
	}

	@Test("The channel key is not part of the encoded value")
	func secretKeyIsNeverEncoded() {
		var config = ChannelConfig(channelName: "#swift")
		config.secretKey = "hunter2"

		#expect(PropertyListModel.encode(config)["secretKey"] == nil)
		#expect(config.pendingSecretKey == "hunter2")
	}
}
