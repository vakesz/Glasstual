// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
import CocoaExtensions
import Foundation
@testable import Glasstual
import Testing

/// A channel writes only the settings that differ from the default, plus its
/// name, identifier and (for anything but a channel) its type — the shape
/// `ce_dictionaryByRemovingDefaults` produced.
@Suite("Channel configuration property-list round trip")
@MainActor
struct ConversationConfigCodableTests {
	@Test("A stored channel re-encodes unchanged")
	func roundTripsAStoredChannel() throws {
		// Captured from the class-based `ConversationConfig.dictionaryValue`.
		let fixture: [String: PropertyListValue] = [
			"name": "#swift",
			"uniqueIdentifier": "8B2F4C1A-0000-4000-8000-000000000006",
			"autoJoin": false,
			"ignoreHighlights": true,
			"defaultTopic": "Swift talk",
		]

		let config = try #require(PropertyListModel.decode(ConversationConfig.self, from: fixture))

		#expect(config.type == .channel)
		#expect(config.autoJoin == false)
		#expect(config.ignoreHighlights)
		#expect(config.defaultTopic == "Swift talk")
		#expect(PropertyListModel.encode(config) == fixture)
	}

	@Test("A stored query keeps only its name, identifier and type")
	func roundTripsAStoredQuery() throws {
		let fixture: [String: PropertyListValue] = [
			"name": "alice",
			"uniqueIdentifier": "8B2F4C1A-0000-4000-8000-000000000007",
			"type": 1,
		]

		let config = try #require(PropertyListModel.decode(ConversationConfig.self, from: fixture))

		#expect(config.type == .direct)
		#expect(PropertyListModel.encode(config) == fixture)
	}

	/// A field nothing declares is not a setting: it decodes to nothing and is
	/// not written back.
	@Test("A key this build does not know leaves the channel on its defaults")
	func unknownKeysAreIgnored() throws {
		let config = try #require(PropertyListModel.decode(ConversationConfig.self, from: [
			"name": "#swift",
			"joinOnConnect": false,
			"enableNotifications": false,
		]))

		#expect(config.autoJoin)
		#expect(config.pushNotifications)

		let encoded = PropertyListModel.encode(config)

		#expect(encoded["joinOnConnect"] == nil)
		#expect(encoded["enableNotifications"] == nil)
	}

	/// The channel's default modes are stored under the name of the property
	/// they set.
	@Test("The default modes round trip under their own name")
	func defaultModesRoundTrip() throws {
		let fixture: [String: PropertyListValue] = [
			"name": "#swift",
			"uniqueIdentifier": "8B2F4C1A-0000-4000-8000-000000000008",
			"defaultModes": "+nt",
		]

		let config = try #require(PropertyListModel.decode(ConversationConfig.self, from: fixture))

		#expect(config.defaultModes == "+nt")
		#expect(PropertyListModel.encode(config) == fixture)
	}

	@Test("An absent optional stays nil rather than becoming an empty string")
	func absentOptionalsStayNil() throws {
		let config = try #require(PropertyListModel.decode(ConversationConfig.self, from: [
			"name": "#swift",
		]))

		#expect(config.label == nil)
		#expect(config.defaultModes == nil)
		#expect(config.defaultTopic == nil)
	}

	@Test("Muting a conversation survives the round trip")
	func muteSurvivesTheRoundTrip() throws {
		var config = ConversationConfig(name: "#swift")
		config.pushNotifications = false

		let restored = try #require(
			PropertyListModel.decode(ConversationConfig.self, from: PropertyListModel.encode(config))
		)

		#expect(restored.pushNotifications == false)
	}

	@Test("Every general-event display choice survives the round trip", arguments: GeneralEventMessageDisplay.allCases)
	func generalEventDisplayRoundTrips(_ display: GeneralEventMessageDisplay) throws {
		var config = ConversationConfig(name: "#swift")
		config.generalEventMessageDisplay = display

		let restored = try #require(
			PropertyListModel.decode(ConversationConfig.self, from: PropertyListModel.encode(config))
		)

		#expect(restored.generalEventMessageDisplay == display)
		#expect(restored.ignoreGeneralEventMessages == (display == .hide))
	}

	@Test("The old hidden-event flag retains its stored shape")
	func legacyHiddenEventsRoundTrip() throws {
		let fixture: [String: PropertyListValue] = [
			"name": "#swift",
			"uniqueIdentifier": "8B2F4C1A-0000-4000-8000-000000000009",
			"ignoreGeneralEventMessages": true,
		]
		let restored = try #require(PropertyListModel.decode(ConversationConfig.self, from: fixture))

		#expect(restored.generalEventMessageDisplay == .hide)
		#expect(PropertyListModel.encode(restored) == fixture)
	}

	@Test("An explicit event display overrides the old hidden-event flag")
	func explicitEventDisplayWins() throws {
		let restored = try #require(PropertyListModel.decode(ConversationConfig.self, from: [
			"name": "#swift",
			"ignoreGeneralEventMessages": true,
			"generalEventMessageDisplay": "collapse",
		]))

		#expect(restored.generalEventMessageDisplay == .collapse)
		#expect(restored.ignoreGeneralEventMessages == false)
	}

	@Test("An unrecognized event display falls back to the old hidden-event setting")
	func unknownEventDisplayUsesLegacyFlag() throws {
		let restored = try #require(PropertyListModel.decode(ConversationConfig.self, from: [
			"name": "#swift",
			"ignoreGeneralEventMessages": true,
			"generalEventMessageDisplay": "future-mode",
		]))

		#expect(restored.generalEventMessageDisplay == .hide)
	}

	@Test("The channel key is not part of the encoded value")
	func secretKeyIsNeverEncoded() {
		var config = ConversationConfig(name: "#swift")
		config.secretKey = "hunter2"

		#expect(PropertyListModel.encode(config)["secretKey"] == nil)
		#expect(config.pendingSecretKey == .set("hunter2"))
	}

	/** `nil` used to mean "no edit" for the channel key, so there was no way to
	 say the key had been removed: flushing an emptied key left the keychain
	 item in place, and the next JOIN sent it again. */
	@Test("Clearing the channel key deletes the stored one when flushed")
	func clearedSecretKeyDeletesTheKeychainItem() async throws {
		var config = ConversationConfig(name: "#swift")
		#expect(config.keychainItem.write("stored-key"))
		defer { config.keychainItem.delete() }

		config.secretKey = ""

		#expect(config.pendingSecretKey == .cleared)
		#expect(config.secretKey == nil)
		#expect(config.uniqueCopy().pendingSecretKey == .cleared)

		let edits = config.pendingKeychainEdits
		try await KeychainWriter.shared.apply(edits)
		config.acknowledgeKeychainEdits(edits)

		#expect(config.pendingSecretKey == .unchanged)
		#expect(config.keychainItem.password == nil)
		#expect(config.secretKey == nil)
	}
}
