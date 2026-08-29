/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
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

@objc public enum IRCAddressBookEntryType: UInt, Sendable, Codable {
	case ignore = 0
	case userTracking = 1
	case mixed = 2
}

@objc public enum IRCAddressBookUserTrackingStatus: UInt, Sendable {
	case unknown = 0
	case signedOff = 1
	case signedOn = 2
	case available = 3
	case notAvailable = 4
	case away = 5
	case notAway = 6
}

/** One address-book rule: a hostmask, what to suppress from whoever matches it,
 and whether to watch them come and go.

 A rule loaded from disk carries only the settings its `entryType` uses, and the
 compiled hostmask matcher is rebuilt whenever the type or the mask changes. */
public nonisolated struct AddressBookEntry: Codable, Equatable { // nonisolated: value
	public var uniqueIdentifier: String

	public var entryType: IRCAddressBookEntryType {
		didSet { rebuildCache() }
	}

	public var hostmask: String {
		didSet { rebuildCache() }
	}

	public var ignoreClientToClientProtocol = false
	public var ignoreFileTransferRequests = false
	public var ignoreGeneralEventMessages = false
	public var ignoreInlineMedia = false
	public var ignoreNoticeMessages = false
	public var ignorePrivateMessageHighlights = false
	public var ignorePrivateMessages = false
	public var ignorePublicMessageHighlights = false
	public var ignorePublicMessages = false
	public var trackUserActivity = false

	/** The rules a `.mixed` entry was merged from. Never persisted: a merged
	 entry only exists in the match cache. */
	public var parentEntries: [AddressBookEntry]?

	private var matcher: AddressBookEntryMatcher

	public init(
		uniqueIdentifier: String = UUID().uuidString,
		entryType: IRCAddressBookEntryType = .ignore,
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
		case trackUserActivity

		// Spellings written by releases before the settings were renamed.
		case ignoreCTCP
		case ignoreJPQE
		case ignoreNotices
		case ignorePMHighlights
		case ignorePrivateMsg
		case ignoreHighlights
		case ignorePublicMsg
		case notifyJoins
	}

	public init(from decoder: any Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)

		let identifier = container.decode(String.self, forKey: .uniqueIdentifier, aliases: [], default: "")
		uniqueIdentifier = identifier.isEmpty ? UUID().uuidString : identifier
		hostmask = container.decode(String.self, forKey: .hostmask, aliases: [], default: "")

		let rawEntryType = container.decode(UInt.self, forKey: .entryType, aliases: [], default: 0)
		let entryType = IRCAddressBookEntryType(rawValue: rawEntryType) ?? .ignore
		self.entryType = entryType
		matcher = AddressBookEntryMatcher(entryType: entryType, hostmask: hostmask)

		if entryType == .ignore || entryType == .mixed {
			decodeIgnoreSettings(from: container)
		}

		if entryType == .userTracking || entryType == .mixed {
			trackUserActivity = container.decode(
				Bool.self,
				forKey: .trackUserActivity,
				aliases: [.notifyJoins],
				default: false
			)
		}
	}

	private mutating func decodeIgnoreSettings(from container: KeyedDecodingContainer<CodingKeys>) {
		ignoreClientToClientProtocol = container.decode(
			Bool.self,
			forKey: .ignoreClientToClientProtocol,
			aliases: [.ignoreCTCP],
			default: false
		)
		ignoreFileTransferRequests = container.decode(
			Bool.self,
			forKey: .ignoreFileTransferRequests,
			aliases: [],
			default: false
		)
		ignoreGeneralEventMessages = container.decode(
			Bool.self,
			forKey: .ignoreGeneralEventMessages,
			aliases: [.ignoreJPQE],
			default: false
		)
		ignoreInlineMedia = container.decode(Bool.self, forKey: .ignoreInlineMedia, aliases: [], default: false)
		ignoreNoticeMessages = container.decode(
			Bool.self,
			forKey: .ignoreNoticeMessages,
			aliases: [.ignoreNotices],
			default: false
		)
		ignorePrivateMessageHighlights = container.decode(
			Bool.self,
			forKey: .ignorePrivateMessageHighlights,
			aliases: [.ignorePMHighlights],
			default: false
		)
		ignorePrivateMessages = container.decode(
			Bool.self,
			forKey: .ignorePrivateMessages,
			aliases: [.ignorePrivateMsg],
			default: false
		)
		ignorePublicMessageHighlights = container.decode(
			Bool.self,
			forKey: .ignorePublicMessageHighlights,
			aliases: [.ignoreHighlights],
			default: false
		)
		ignorePublicMessages = container.decode(
			Bool.self,
			forKey: .ignorePublicMessages,
			aliases: [.ignorePublicMsg],
			default: false
		)
	}

	/** Writes the canonical keys only, and only those that differ from the
	 default. Earlier releases compacted the dictionary the same way, so a
	 stored entry re-encodes to exactly what is already on disk. */
	public func encode(to encoder: any Encoder) throws {
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
		]

		for (value, key) in settings where value {
			try container.encode(true, forKey: key)
		}
	}

	public static func == (lhs: Self, rhs: Self) -> Bool {
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
			&& lhs.trackUserActivity == rhs.trackUserActivity
	}
}

public nonisolated extension AddressBookEntry { // nonisolated: value
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
