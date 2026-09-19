// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation

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
		case matchChannelId
		case matchIsExcluded
	}

	init(from decoder: any Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)

		let identifier = container.decode(String.self, forKey: .uniqueIdentifier, default: "")
		uniqueIdentifier = identifier.isEmpty ? UUID().uuidString : identifier
		matchKeyword = container.decode(String.self, forKey: .matchKeyword, default: "")
		matchChannelId = container.decodeOptional(String.self, forKey: .matchChannelId)
		matchIsExcluded = container.decode(Bool.self, forKey: .matchIsExcluded, default: false)
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
