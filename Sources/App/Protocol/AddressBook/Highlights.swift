// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation
import os

private let highlightLogEntryLogger = Logger(
	subsystem: Bundle.main.bundleIdentifier ?? "Glasstual",
	category: "IRCHighlightLogEntry"
)

/** An entry in a client's in-memory highlight log.

 A value, owned by the client that logged it (`Client.cachedHighlights`) and
 read by `ServerHighlightList`, which sorts and draws the entries itself
 rather than binding an `NSArrayController` to them by KVC key path.

 Its identity is the line it logged: `lineNumber` names one printed line. */
struct HighlightLogEntry: Codable, Hashable, Sendable {
	var lineLogged: LogLine
	var clientId: String
	var channelId: String

	init(lineLogged: LogLine, clientId: String, channelId: String) {
		self.lineLogged = lineLogged
		self.clientId = clientId
		self.channelId = channelId

		// An incomplete entry used to abort the app from a health check; it is
		// only logged now, and callers that care check `isWellFormed`.
		if isWellFormed == false {
			highlightLogEntryLogger.error("Created an incomplete highlight log entry")
		}
	}

	/// `true` when the entry carries everything its accessors need.
	var isWellFormed: Bool {
		clientId.isEmpty == false && channelId.isEmpty == false
	}

	var timeLogged: Date {
		lineLogged.receivedAt
	}

	var lineNumber: String {
		lineLogged.uniqueIdentifier
	}
}

/** One keyword a connection watches for, optionally scoped to one channel.

 A condition with no keyword can never match. Persisted lists are filtered on
 load rather than rejected, so a hand-edited property list drops the broken
 entry instead of aborting the app. */
nonisolated struct HighlightMatchCondition: Codable, Sendable, Equatable, Hashable {
	var uniqueIdentifier: String
	var matchKeyword: String
	var matchChannelId: String?
	var matchIsExcluded: Bool

	init(
		uniqueIdentifier: String = UUID().uuidString,
		matchKeyword: String = "",
		matchChannelId: String? = nil,
		matchIsExcluded: Bool = false
	) {
		self.uniqueIdentifier = uniqueIdentifier
		self.matchKeyword = matchKeyword
		self.matchChannelId = matchChannelId
		self.matchIsExcluded = matchIsExcluded
	}

	private enum CodingKeys: String, CodingKey {
		case uniqueIdentifier
		case matchKeyword
		// Spelled with a capitalised ID on disk since the Objective-C original.
		case matchChannelId = "matchChannelID"
		case matchIsExcluded
	}

	init(from decoder: any Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)

		let identifier = container.decode(String.self, forKey: .uniqueIdentifier, aliases: [], default: "")
		uniqueIdentifier = identifier.isEmpty ? UUID().uuidString : identifier
		matchKeyword = container.decode(String.self, forKey: .matchKeyword, aliases: [], default: "")
		matchChannelId = container.decodeOptional(String.self, forKey: .matchChannelId)
		matchIsExcluded = container.decode(Bool.self, forKey: .matchIsExcluded, aliases: [], default: false)
	}

	func encode(to encoder: any Encoder) throws {
		var container = encoder.container(keyedBy: CodingKeys.self)

		try container.encodeIfPresent(matchChannelId, forKey: .matchChannelId)
		try container.encode(matchKeyword, forKey: .matchKeyword)
		try container.encode(uniqueIdentifier, forKey: .uniqueIdentifier)
		try container.encode(matchIsExcluded, forKey: .matchIsExcluded)
	}

	/// `true` when the condition carries everything a match needs.
	var isWellFormed: Bool {
		matchKeyword.isEmpty == false
	}

	/// A copy under a fresh identity.
	func uniqueCopy() -> HighlightMatchCondition {
		var copy = self
		copy.uniqueIdentifier = UUID().uuidString

		return copy
	}
}
