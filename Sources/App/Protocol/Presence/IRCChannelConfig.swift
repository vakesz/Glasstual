/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 *
 *  * Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 *  * Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 *  * Neither the name of Textual, "Codeux Software, LLC", nor the
 *    names of its contributors may be used to endorse or promote products
 *    derived from this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED. IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
 * FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
 * OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
 * LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
 * OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
 * SUCH DAMAGE.
 *
 *********************************************************************** */

import CocoaExtensions
import Foundation
import GlasstualPluginKit

/** A channel's answer to one notification setting.

 A channel either turns the setting on, turns it off, or says nothing and lets
 the application-wide preference answer. Keeping that choice in the protocol
 model means neither persistence nor the editor depends on AppKit controls. */
public nonisolated enum ChannelEventOverride: CaseIterable, Sendable, Equatable, Hashable { // nonisolated: value
	case on
	case off
	/// No override: whatever the application-wide preference says.
	case inherited
}

/// One notification override a channel carries: either a sound name or an
/// on/off flag. A channel with no override for an event inherits the
/// application-wide setting, which the sheets show as a mixed checkbox.
public nonisolated enum ChannelNotificationSetting: Codable, Sendable, Equatable, Hashable { // nonisolated: value
	case sound(String)
	case flag(Bool)

	public init(from decoder: any Decoder) throws {
		let container = try decoder.singleValueContainer()

		if let flag = try? container.decode(Bool.self) {
			self = .flag(flag)
		} else {
			self = try .sound(container.decode(String.self))
		}
	}

	public func encode(to encoder: any Encoder) throws {
		var container = encoder.singleValueContainer()

		switch self {
		case let .sound(name): try container.encode(name)
		case let .flag(value): try container.encode(value)
		}
	}
}

/** A channel or query as its connection stores it.

 A query keeps only its name, identifier and type; the channel settings below
 are read and written only for `.channel`, which is what earlier releases did
 and what keeps a stored configuration re-encoding unchanged. */
public nonisolated struct ChannelConfig: Codable, Sendable, Equatable, Hashable { // nonisolated: value
	public var uniqueIdentifier: String
	public var channelName: String
	public var type: ChannelType

	public var autoJoin = true
	public var ignoreGeneralEventMessages = false
	public var ignoreHighlights = false
	public var inlineMediaDisabled = false
	public var inlineMediaEnabled = false
	public var pushNotifications = true
	public var showTreeBadgeCount = true

	public var label: String?
	public var defaultModes: String?
	public var defaultTopic: String?

	/// Per-event overrides, keyed by the notification preference schema.
	public var notifications: [String: ChannelNotificationSetting] = [:]

	/** A channel key waiting to be written to the keychain, or one read back
	 out of it so a duplicate can carry it to its own identifier. Never
	 encoded — see `secretKey`. */
	public var pendingSecretKey: String?

	public init(
		uniqueIdentifier: String = UUID().uuidString,
		channelName: String = "",
		type: ChannelType = .channel
	) {
		self.uniqueIdentifier = uniqueIdentifier
		self.channelName = channelName
		self.type = type
	}

	public static func seed(withName channelName: String) -> ChannelConfig {
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
		case notifications

		// Spellings written by releases before these settings were renamed.
		case joinOnConnect
		case ignoreJPQActivity
		case enableNotifications
		case enableTreeBadgeCountDrawing
		case ignoreInlineMedia
	}

	public init(from decoder: any Decoder) throws {
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
		notifications = container.decodeOptional(
			[String: ChannelNotificationSetting].self,
			forKey: .notifications
		) ?? [:]

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
	public func encode(to encoder: any Encoder) throws {
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
		// Written even when empty, as it always has been.
		try container.encode(notifications, forKey: .notifications)

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

public nonisolated extension ChannelConfig { // nonisolated: value
	var keychainItem: KeychainItem {
		.channelSecretKey(uniqueIdentifier)
	}

	var secretKeyFromKeychain: String? {
		keychainItem.password
	}

	/// The key to JOIN with: an unflushed edit if there is one, and otherwise
	/// whatever the keychain holds.
	var secretKey: String? {
		get { pendingSecretKey ?? secretKeyFromKeychain }
		set { pendingSecretKey = newValue }
	}

	mutating func writeSecretKeyToKeychain() {
		guard let pendingSecretKey else {
			return
		}

		keychainItem.write(pendingSecretKey)
		self.pendingSecretKey = nil
	}

	mutating func destroySecretKeyKeychainItem() {
		keychainItem.delete()
		pendingSecretKey = nil
	}

	/// A copy under a fresh identity, carrying the channel key across so the
	/// duplicate does not silently lose it.
	func uniqueCopy() -> ChannelConfig {
		var copy = self
		copy.pendingSecretKey = pendingSecretKey ?? secretKeyFromKeychain
		copy.uniqueIdentifier = UUID().uuidString

		return copy
	}

	func sound(forEvent event: TXNotificationType) -> String? {
		guard case let .sound(name) = notifications[event.preferenceKeyName(for: .sound)]
		else {
			return nil
		}

		return name
	}

	func notificationEnabled(forEvent event: TXNotificationType) -> ChannelEventOverride {
		state(for: event, setting: .enabled)
	}

	func disabledWhileAway(forEvent event: TXNotificationType) -> ChannelEventOverride {
		state(for: event, setting: .disabledWhileAway)
	}

	func bounceDockIcon(forEvent event: TXNotificationType) -> ChannelEventOverride {
		state(for: event, setting: .bounceDockIcon)
	}

	func bounceDockIconRepeatedly(forEvent event: TXNotificationType) -> ChannelEventOverride {
		state(for: event, setting: .bounceDockIconRepeatedly)
	}

	func speakEvent(_ event: TXNotificationType) -> ChannelEventOverride {
		state(for: event, setting: .speak)
	}

	mutating func setSound(_ value: String?, forEvent event: TXNotificationType) {
		notifications[event.preferenceKeyName(for: .sound)] = value.map(ChannelNotificationSetting.sound)
	}

	mutating func setNotificationEnabled(_ value: ChannelEventOverride, forEvent event: TXNotificationType) {
		setState(value, forEvent: event, setting: .enabled)
	}

	mutating func setDisabledWhileAway(_ value: ChannelEventOverride, forEvent event: TXNotificationType) {
		setState(value, forEvent: event, setting: .disabledWhileAway)
	}

	mutating func setBounceDockIcon(_ value: ChannelEventOverride, forEvent event: TXNotificationType) {
		setState(value, forEvent: event, setting: .bounceDockIcon)
	}

	mutating func setBounceDockIconRepeatedly(_ value: ChannelEventOverride, forEvent event: TXNotificationType) {
		setState(value, forEvent: event, setting: .bounceDockIconRepeatedly)
	}

	mutating func setEventIsSpoken(_ value: ChannelEventOverride, forEvent event: TXNotificationType) {
		setState(value, forEvent: event, setting: .speak)
	}

	private mutating func setState(
		_ value: ChannelEventOverride,
		forEvent event: TXNotificationType,
		setting: NotificationSetting
	) {
		let key = event.preferenceKeyName(for: setting)

		switch value {
		case .on:
			notifications[key] = .flag(true)
		case .off:
			notifications[key] = .flag(false)
		case .inherited:
			notifications.removeValue(forKey: key)
		}
	}

	private func state(for event: TXNotificationType, setting: NotificationSetting) -> ChannelEventOverride {
		guard case let .flag(value) = notifications[event.preferenceKeyName(for: setting)]
		else {
			return .inherited
		}

		return value ? .on : .off
	}
}
