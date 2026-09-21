// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation

enum AddressBookEntryKind: UInt, Sendable, Codable {
	case ignore = 0
	case userTracking = 1
	case mixed = 2
}

/** One address-book rule: a hostmask, what to suppress from whoever matches it,
 and whether to watch them come and go.

 A rule loaded from disk carries only the settings its `entryType` uses, and the
 compiled hostmask matcher is rebuilt whenever the type or the mask changes. The
 `.mixed` type is never stored: it only exists in the match cache. */
nonisolated struct AddressBookEntry: Codable, Equatable, Sendable {
	var uniqueIdentifier: String

	var entryType: AddressBookEntryKind {
		didSet { rebuildCache() }
	}

	var hostmask: String {
		didSet { rebuildCache() }
	}

	var ignoreClientToClientProtocol = false
	var ignoreFileTransferRequests = false
	var ignoreGeneralEventMessages = false
	var ignoreInlineMedia = false
	var ignoreNoticeMessages = false
	var ignorePrivateMessageHighlights = false
	var ignorePrivateMessages = false
	var ignorePublicMessageHighlights = false
	var ignorePublicMessages = false
	var muteMessages = false
	var trackUserActivity = false

	/** The rules a `.mixed` entry was merged from. Never persisted: a merged
	 entry only exists in the match cache. */
	var parentEntries: [AddressBookEntry]?

	private var matcher: AddressBookEntryMatcher

	init(
		uniqueIdentifier: String = UUID().uuidString,
		entryType: AddressBookEntryKind = .ignore,
		hostmask: String = ""
	) {
		self.uniqueIdentifier = uniqueIdentifier
		self.entryType = entryType
		self.hostmask = hostmask
		matcher = AddressBookEntryMatcher(entryType: entryType, hostmask: hostmask)
	}

	private enum CodingKeys: String, CodingKey {
		case uniqueIdentifier
		case entryType
		case hostmask
		case ignoreClientToClientProtocol
		case ignoreFileTransferRequests
		case ignoreGeneralEventMessages
		case ignoreInlineMedia
		case ignoreNoticeMessages
		case ignorePrivateMessageHighlights
		case ignorePrivateMessages
		case ignorePublicMessageHighlights
		case ignorePublicMessages
		case muteMessages
		case trackUserActivity
	}

	init(from decoder: any Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)

		let identifier = container.decode(String.self, forKey: .uniqueIdentifier, default: "")
		uniqueIdentifier = identifier.isEmpty ? UUID().uuidString : identifier
		hostmask = container.decode(String.self, forKey: .hostmask, default: "")

		let rawEntryType = container.decode(UInt.self, forKey: .entryType, default: 0)
		let entryType = AddressBookEntryKind(rawValue: rawEntryType) ?? .ignore
		self.entryType = entryType
		matcher = AddressBookEntryMatcher(entryType: entryType, hostmask: hostmask)

		if entryType == .ignore || entryType == .mixed {
			decodeIgnoreSettings(from: container)
		}

		if entryType == .userTracking || entryType == .mixed {
			trackUserActivity = container.decode(Bool.self, forKey: .trackUserActivity, default: false)
		}
	}

	private mutating func decodeIgnoreSettings(from container: KeyedDecodingContainer<CodingKeys>) {
		ignoreClientToClientProtocol = container.decode(
			Bool.self,
			forKey: .ignoreClientToClientProtocol,
			default: false
		)
		ignoreFileTransferRequests = container.decode(Bool.self, forKey: .ignoreFileTransferRequests, default: false)
		ignoreGeneralEventMessages = container.decode(Bool.self, forKey: .ignoreGeneralEventMessages, default: false)
		ignoreInlineMedia = container.decode(Bool.self, forKey: .ignoreInlineMedia, default: false)
		ignoreNoticeMessages = container.decode(Bool.self, forKey: .ignoreNoticeMessages, default: false)
		ignorePrivateMessageHighlights = container.decode(
			Bool.self,
			forKey: .ignorePrivateMessageHighlights,
			default: false
		)
		ignorePrivateMessages = container.decode(Bool.self, forKey: .ignorePrivateMessages, default: false)
		ignorePublicMessageHighlights = container.decode(
			Bool.self,
			forKey: .ignorePublicMessageHighlights,
			default: false
		)
		ignorePublicMessages = container.decode(Bool.self, forKey: .ignorePublicMessages, default: false)
		muteMessages = container.decode(Bool.self, forKey: .muteMessages, default: false)
	}

	/// Writes only the settings that differ from their default, so a stored
	/// entry re-encodes to exactly the dictionary it was read from.
	func encode(to encoder: any Encoder) throws {
		var container = encoder.container(keyedBy: CodingKeys.self)

		if hostmask.isEmpty == false {
			try container.encode(hostmask, forKey: .hostmask)
		}

		if uniqueIdentifier.isEmpty == false {
			try container.encode(uniqueIdentifier, forKey: .uniqueIdentifier)
		}

		if entryType == .ignore || entryType == .mixed {
			try encodeIgnoreSettings(into: &container)
		}

		if entryType == .userTracking || entryType == .mixed, trackUserActivity {
			try container.encode(true, forKey: .trackUserActivity)
		}

		if entryType != .ignore {
			try container.encode(entryType.rawValue, forKey: .entryType)
		}
	}

	private func encodeIgnoreSettings(into container: inout KeyedEncodingContainer<CodingKeys>) throws {
		let settings: [(Bool, CodingKeys)] = [
			(ignoreClientToClientProtocol, .ignoreClientToClientProtocol),
			(ignoreFileTransferRequests, .ignoreFileTransferRequests),
			(ignoreGeneralEventMessages, .ignoreGeneralEventMessages),
			(ignoreInlineMedia, .ignoreInlineMedia),
			(ignoreNoticeMessages, .ignoreNoticeMessages),
			(ignorePrivateMessageHighlights, .ignorePrivateMessageHighlights),
			(ignorePrivateMessages, .ignorePrivateMessages),
			(ignorePublicMessageHighlights, .ignorePublicMessageHighlights),
			(ignorePublicMessages, .ignorePublicMessages),
			(muteMessages, .muteMessages),
		]

		for (value, key) in settings where value {
			try container.encode(true, forKey: key)
		}
	}

	static func == (lhs: Self, rhs: Self) -> Bool {
		lhs.uniqueIdentifier == rhs.uniqueIdentifier
			&& lhs.entryType == rhs.entryType
			&& lhs.hostmask == rhs.hostmask
			&& lhs.ignoreClientToClientProtocol == rhs.ignoreClientToClientProtocol
			&& lhs.ignoreFileTransferRequests == rhs.ignoreFileTransferRequests
			&& lhs.ignoreGeneralEventMessages == rhs.ignoreGeneralEventMessages
			&& lhs.ignoreInlineMedia == rhs.ignoreInlineMedia
			&& lhs.ignoreNoticeMessages == rhs.ignoreNoticeMessages
			&& lhs.ignorePrivateMessageHighlights == rhs.ignorePrivateMessageHighlights
			&& lhs.ignorePrivateMessages == rhs.ignorePrivateMessages
			&& lhs.ignorePublicMessageHighlights == rhs.ignorePublicMessageHighlights
			&& lhs.ignorePublicMessages == rhs.ignorePublicMessages
			&& lhs.muteMessages == rhs.muteMessages
			&& lhs.trackUserActivity == rhs.trackUserActivity
	}
}

nonisolated extension AddressBookEntry {
	/// Muting keeps messages in history. These flags instead discard events.
	var ignoresEvents: Bool {
		ignoreClientToClientProtocol || ignoreFileTransferRequests || ignoreGeneralEventMessages
			|| ignoreInlineMedia || ignoreNoticeMessages || ignorePrivateMessageHighlights
			|| ignorePrivateMessages || ignorePublicMessageHighlights || ignorePublicMessages
	}

	/// An entry that suppresses everything from `hostmask`.
	static func newIgnoreEntry(forHostmask hostmask: String? = nil) -> AddressBookEntry {
		var entry = AddressBookEntry(entryType: .ignore, hostmask: hostmask ?? "")
		entry.ignoreClientToClientProtocol = true
		entry.ignoreFileTransferRequests = true
		entry.ignoreGeneralEventMessages = true
		entry.ignoreInlineMedia = true
		entry.ignoreNoticeMessages = true
		entry.ignorePrivateMessageHighlights = true
		entry.ignorePrivateMessages = true
		entry.ignorePublicMessageHighlights = true
		entry.ignorePublicMessages = true

		return entry
	}

	/// An entry that only watches whoever matches it come and go.
	static func newUserTrackingEntry() -> AddressBookEntry {
		var entry = AddressBookEntry(entryType: .userTracking)
		entry.trackUserActivity = true

		return entry
	}

	var hostmaskRegularExpression: String {
		matcher.regularExpressionPattern
	}

	var trackingNickname: String? {
		matcher.trackingNickname
	}

	func checkMatch(_ hostmask: String) -> Bool {
		matcher.matches(hostmask: hostmask)
	}

	/// Session-owned mute rules use the server's advertised nickname mapping.
	/// Legacy ignore and tracking lookups keep their existing default mapping.
	func checkMatch(_ hostmask: String, caseMapping: ISupportCaseMapping) -> Bool {
		AddressBookEntryMatcher(entryType: entryType, hostmask: self.hostmask, caseMapping: caseMapping)
			.matches(hostmask: hostmask)
	}

	/// A copy under a fresh identity.
	func uniqueCopy() -> AddressBookEntry {
		var copy = self
		copy.uniqueIdentifier = UUID().uuidString

		return copy
	}

	private mutating func rebuildCache() {
		matcher = AddressBookEntryMatcher(entryType: entryType, hostmask: hostmask)
	}
}
