// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation

/** A channel or query as its connection stores it.

 A query keeps only its name, identifier and type; the channel settings below
 are read and written only for `.channel`, which is what earlier releases did
 and what keeps a stored configuration re-encoding unchanged. */
nonisolated struct ChannelConfig: Codable, Sendable, Equatable, Hashable {
	var uniqueIdentifier: String
	var channelName: String
	var type: ChannelType

	var autoJoin = true
	var ignoreGeneralEventMessages = false
	/// Whether a mention in this channel is worth interrupting for.
	var ignoreHighlights = false
	var inlineMediaDisabled = false
	var inlineMediaEnabled = false
	/// Whether this conversation notifies at all. The Messages "Hide Alerts"
	/// switch, under the name it has always been stored as.
	var pushNotifications = true
	var showTreeBadgeCount = true

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
		channelName: String = "",
		type: ChannelType = .channel
	) {
		self.uniqueIdentifier = uniqueIdentifier
		self.channelName = channelName
		self.type = type
	}

	static func seed(withName channelName: String) -> ChannelConfig {
		ChannelConfig(channelName: channelName)
	}

	private enum CodingKeys: String, CodingKey {
		case uniqueIdentifier
		case channelName
		case channelType
		case autoJoin
		case ignoreGeneralEventMessages
		case ignoreHighlights
		case inlineMediaDisabled
		case inlineMediaEnabled
		case pushNotifications
		case showTreeBadgeCount
		case label
		case defaultModes = "defaultMode"
		case defaultTopic

		// Spellings written by releases before these settings were renamed.
		case joinOnConnect
		case ignoreJPQActivity
		case enableNotifications
		case enableTreeBadgeCountDrawing
		case ignoreInlineMedia
	}

	init(from decoder: any Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)

		let identifier = container.decode(String.self, forKey: .uniqueIdentifier, aliases: [], default: "")
		uniqueIdentifier = identifier.isEmpty ? UUID().uuidString : identifier
		channelName = container.decode(String.self, forKey: .channelName, aliases: [], default: "")
		type = ChannelType(rawValue: container.decode(UInt.self, forKey: .channelType, aliases: [], default: 0))
			?? .channel
		pushNotifications = container.decode(
			Bool.self,
			forKey: .pushNotifications,
			aliases: [.enableNotifications],
			default: true
		)
		showTreeBadgeCount = container.decode(
			Bool.self,
			forKey: .showTreeBadgeCount,
			aliases: [.enableTreeBadgeCountDrawing],
			default: true
		)

		guard type == .channel else {
			return
		}

		decodeChannelSettings(from: container)
	}

	private mutating func decodeChannelSettings(from container: KeyedDecodingContainer<CodingKeys>) {
		autoJoin = container.decode(Bool.self, forKey: .autoJoin, aliases: [.joinOnConnect], default: true)
		ignoreGeneralEventMessages = container.decode(
			Bool.self,
			forKey: .ignoreGeneralEventMessages,
			aliases: [.ignoreJPQActivity],
			default: false
		)
		ignoreHighlights = container.decode(Bool.self, forKey: .ignoreHighlights, aliases: [], default: false)
		label = container.decodeOptional(String.self, forKey: .label)
		defaultModes = container.decodeOptional(String.self, forKey: .defaultModes)
		defaultTopic = container.decodeOptional(String.self, forKey: .defaultTopic)
		decodeInlineMediaSettings(from: container)
	}

	/** Before these two settings existed a channel only recorded that it opted
	 out of inline media, which meant the opposite of the application-wide
	 setting. Both keys being present means the migration already ran. */
	private mutating func decodeInlineMediaSettings(from container: KeyedDecodingContainer<CodingKeys>) {
		let storedDisabled = container.decodeOptional(Bool.self, forKey: .inlineMediaDisabled)
		let storedEnabled = container.decodeOptional(Bool.self, forKey: .inlineMediaEnabled)

		inlineMediaDisabled = storedDisabled ?? false
		inlineMediaEnabled = storedEnabled ?? false

		guard storedDisabled == nil || storedEnabled == nil,
		      container.decodeOptional(Bool.self, forKey: .ignoreInlineMedia) == true
		else {
			return
		}

		inlineMediaDisabled = Preferences.Messages.showInlineMedia.detachedValue
		inlineMediaEnabled = inlineMediaDisabled == false
	}

	/** Writes the canonical keys only, and only those that differ from the
	 default — the same dictionary `ce_dictionaryByRemovingDefaults` produced. */
	func encode(to encoder: any Encoder) throws {
		var container = encoder.container(keyedBy: CodingKeys.self)

		if pushNotifications == false {
			try container.encode(false, forKey: .pushNotifications)
		}

		if showTreeBadgeCount == false {
			try container.encode(false, forKey: .showTreeBadgeCount)
		}

		if type == .channel {
			try encodeChannelSettings(into: &container)
		}

		try container.encode(channelName, forKey: .channelName)
		try container.encode(uniqueIdentifier, forKey: .uniqueIdentifier)

		if type != .channel {
			try container.encode(type.rawValue, forKey: .channelType)
		}
	}

	private func encodeChannelSettings(into container: inout KeyedEncodingContainer<CodingKeys>) throws {
		try container.encodeIfPresent(label, forKey: .label)
		try container.encodeIfPresent(defaultModes, forKey: .defaultModes)
		try container.encodeIfPresent(defaultTopic, forKey: .defaultTopic)
		if autoJoin == false {
			try container.encode(false, forKey: .autoJoin)
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

nonisolated extension ChannelConfig {
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

	@discardableResult
	mutating func writeSecretKeyToKeychain() -> KeychainWriteResult {
		let result = keychainItem.apply(pendingSecretKey)
		if result == .saved {
			pendingSecretKey = .unchanged
		}
		return result
	}

	@discardableResult
	mutating func destroySecretKeyKeychainItem() -> KeychainWriteResult {
		pendingSecretKey = .cleared
		let result = keychainItem.apply(pendingSecretKey)
		if result == .saved {
			pendingSecretKey = .unchanged
		}
		return result
	}

	/// A copy under a fresh identity, carrying the channel key across so the
	/// duplicate does not silently lose it.
	func uniqueCopy() -> ChannelConfig {
		var copy = self
		copy.pendingSecretKey = pendingSecretKey.detached(from: secretKeyFromKeychain)
		copy.uniqueIdentifier = UUID().uuidString

		return copy
	}
}
