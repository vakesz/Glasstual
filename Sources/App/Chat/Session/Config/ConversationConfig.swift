// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation

/** A conversation as its connection stores it.

 A conversation that is not a channel keeps only its name, identifier and kind;
 the channel settings below are read and written only for `.channel`, so it
 carries nothing it cannot use. */
nonisolated struct ConversationConfig: Codable, Sendable, Equatable, Hashable {
	var uniqueIdentifier: String
	var name: String
	var type: ConversationKind

	var autoJoin = true
	var generalEventMessageDisplay: GeneralEventMessageDisplay = .show
	/// The inbound filter only drops events when they are hidden completely.
	var ignoreGeneralEventMessages: Bool {
		get { generalEventMessageDisplay == .hide }
		set { generalEventMessageDisplay = newValue ? .hide : .show }
	}

	/// Whether a mention in this channel is worth interrupting for.
	var ignoreHighlights = false
	var inlineMediaDisabled = false
	var inlineMediaEnabled = false
	/// Whether this conversation notifies at all. The Messages "Hide Alerts"
	/// switch, under the name it has always been stored as.
	var pushNotifications = true
	var showsUnreadCount = true
	/// A pinned channel or direct conversation stays available across launches.
	var isFavorite = false

	var label: String?
	var defaultModes: String?
	var defaultTopic: String?

	/** An unflushed edit to the channel key: one waiting to be written to the
	 keychain, a request to delete the stored one, or a stored key read back so
	 a duplicate can carry it to its own identifier. Never encoded — see
	 `secretKey`. */
	var pendingSecretKey: PendingKeychainSecret = .unchanged

	init(
		uniqueIdentifier: String = UUID().uuidString,
		name: String = "",
		type: ConversationKind = .channel
	) {
		self.uniqueIdentifier = uniqueIdentifier
		self.name = name
		self.type = type
	}

	/// The memberwise initialiser as a function value, so a list of names maps
	/// straight onto a list of configurations.
	static func seed(withName name: String) -> ConversationConfig {
		ConversationConfig(name: name)
	}

	/** How a conversation's configuration is spelled on disk.

	 Every key is the name of the property it sets. They are declared rather
	 than synthesized so that renaming a property is a deliberate act: the
	 stored session list and every exported configuration are keyed by these
	 strings. */
	private enum CodingKeys: String, CodingKey {
		case uniqueIdentifier
		case name
		case type
		case autoJoin
		case ignoreGeneralEventMessages
		case generalEventMessageDisplay
		case ignoreHighlights
		case inlineMediaDisabled
		case inlineMediaEnabled
		case pushNotifications
		case showsUnreadCount
		case isFavorite
		case label
		case defaultModes
		case defaultTopic
	}

	init(from decoder: any Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)

		let identifier = container.decode(String.self, forKey: .uniqueIdentifier, default: "")
		uniqueIdentifier = identifier.isEmpty ? UUID().uuidString : identifier
		name = container.decode(String.self, forKey: .name, default: "")
		type = ConversationKind(rawValue: container.decode(UInt.self, forKey: .type, default: 0)) ?? .channel
		pushNotifications = container.decode(Bool.self, forKey: .pushNotifications, default: true)
		showsUnreadCount = container.decode(Bool.self, forKey: .showsUnreadCount, default: true)
		isFavorite = container.decode(Bool.self, forKey: .isFavorite, default: false)

		guard type == .channel else {
			return
		}

		decodeChannelSettings(from: container)
	}

	private mutating func decodeChannelSettings(from container: KeyedDecodingContainer<CodingKeys>) {
		autoJoin = container.decode(Bool.self, forKey: .autoJoin, default: true)
		let legacyHidesEvents = container.decode(Bool.self, forKey: .ignoreGeneralEventMessages, default: false)
		generalEventMessageDisplay = container.decode(
			GeneralEventMessageDisplay.self,
			forKey: .generalEventMessageDisplay,
			default: legacyHidesEvents ? .hide : .show
		)
		ignoreHighlights = container.decode(Bool.self, forKey: .ignoreHighlights, default: false)
		inlineMediaDisabled = container.decode(Bool.self, forKey: .inlineMediaDisabled, default: false)
		inlineMediaEnabled = container.decode(Bool.self, forKey: .inlineMediaEnabled, default: false)
		label = container.decodeOptional(String.self, forKey: .label)
		defaultModes = container.decodeOptional(String.self, forKey: .defaultModes)
		defaultTopic = container.decodeOptional(String.self, forKey: .defaultTopic)
	}

	/// Writes only the settings that differ from their default, so a stored
	/// channel re-encodes to exactly the dictionary it was read from.
	func encode(to encoder: any Encoder) throws {
		var container = encoder.container(keyedBy: CodingKeys.self)

		if pushNotifications == false {
			try container.encode(false, forKey: .pushNotifications)
		}

		if isFavorite {
			try container.encode(true, forKey: .isFavorite)
		}

		if showsUnreadCount == false {
			try container.encode(false, forKey: .showsUnreadCount)
		}

		if type == .channel {
			try encodeChannelSettings(into: &container)
		}

		try container.encode(name, forKey: .name)
		try container.encode(uniqueIdentifier, forKey: .uniqueIdentifier)

		if type != .channel {
			try container.encode(type.rawValue, forKey: .type)
		}
	}

	private func encodeChannelSettings(into container: inout KeyedEncodingContainer<CodingKeys>) throws {
		try container.encodeIfPresent(label, forKey: .label)
		try container.encodeIfPresent(defaultModes, forKey: .defaultModes)
		try container.encodeIfPresent(defaultTopic, forKey: .defaultTopic)
		if autoJoin == false {
			try container.encode(false, forKey: .autoJoin)
		}
		// Keep the existing show/hide archive format; only collapse needs a new key.
		if generalEventMessageDisplay == .collapse {
			try container.encode(generalEventMessageDisplay, forKey: .generalEventMessageDisplay)
		}

		let flags: [(Bool, CodingKeys)] = [
			(ignoreGeneralEventMessages, .ignoreGeneralEventMessages),
			(ignoreHighlights, .ignoreHighlights),
			(inlineMediaDisabled, .inlineMediaDisabled),
			(inlineMediaEnabled, .inlineMediaEnabled),
		]

		for (value, key) in flags where value {
			try container.encode(true, forKey: key)
		}
	}
}

nonisolated extension ConversationConfig {
	var keychainItem: KeychainItem {
		.channelSecretKey(uniqueIdentifier)
	}

	var secretKeyFromKeychain: String? {
		keychainItem.password
	}

	/** The key to JOIN with: an unflushed edit if there is one, and otherwise
	 whatever the keychain holds.

	 Assigning `nil` or an empty key clears it, so an emptied field deletes the
	 stored key instead of falling back to it on every later JOIN. */
	var secretKey: String? {
		get { pendingSecretKey.value(orStored: secretKeyFromKeychain) }
		set { pendingSecretKey = PendingKeychainSecret(newValue) }
	}

	/// A copy under a fresh identity, carrying the channel key across so the
	/// duplicate does not silently lose it.
	func uniqueCopy() -> ConversationConfig {
		var copy = self
		copy.pendingSecretKey = pendingSecretKey.detached(from: secretKeyFromKeychain)
		copy.uniqueIdentifier = UUID().uuidString

		return copy
	}
}
