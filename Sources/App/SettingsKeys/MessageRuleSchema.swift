// Copyright (c) 2015 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation

nonisolated enum MessageRuleDestination: UInt, CaseIterable, Identifiable, Sendable {
	case unrestricted = 0
	case channels = 1
	case privateMessages = 2
	case specificItems = 3

	var id: Self {
		self
	}
}

nonisolated enum MessageRuleAgeComparator: UInt, CaseIterable, Identifiable, Sendable {
	case none = 0
	case lessThan = 1
	case greaterThan = 2

	var id: Self {
		self
	}
}

nonisolated struct MessageRuleEvent: OptionSet, Sendable {
	let rawValue: UInt

	static let plainTextMessage = Self(rawValue: 1 << 1)
	static let actionMessage = Self(rawValue: 1 << 2)
	static let noticeMessage = Self(rawValue: 1 << 3)
	static let userJoinedChannel = Self(rawValue: 1 << 4)
	static let userLeftChannel = Self(rawValue: 1 << 5)
	static let userKickedFromChannel = Self(rawValue: 1 << 6)
	static let userDisconnected = Self(rawValue: 1 << 7)
	static let userChangedNickname = Self(rawValue: 1 << 8)
	static let channelTopicReceived = Self(rawValue: 1 << 9)
	static let channelTopicChanged = Self(rawValue: 1 << 10)
	static let channelModeReceived = Self(rawValue: 1 << 11)
	static let channelModeChanged = Self(rawValue: 1 << 12)

	/// The stored event bits understood by this version of the rule engine.
	static let all: Self = [
		.plainTextMessage, .actionMessage, .noticeMessage, .userJoinedChannel,
		.userLeftChannel, .userKickedFromChannel, .userDisconnected, .userChangedNickname,
		.channelTopicReceived, .channelTopicChanged, .channelModeReceived, .channelModeChanged,
	]

	static let defaultMessages: Self = [.plainTextMessage, .actionMessage]
}

/** The name each field of a stored message rule is written under.

 Declared once: the reader, the writer, the repair that salvages a stored rule
 list and the import preview all reach a field through this and nowhere else, so
 a rename is a compiler error rather than a silently dropped setting. */
nonisolated enum RuleField: String {
	case uniqueIdentifier
	case title
	case match
	case senderMatch
	case notes
	case action
	case forwardDestination
	case additionalCommands
	case limitedChannelIDs
	case limitedSessionIDs
	case ignoresContent
	case ignoresOperators
	case limitedToMyself
	case logsMatch
	case destination
	case ageComparator
	case ageLimit
	case actionFloodControlInterval
	case events
}

nonisolated extension [String: PropertyListValue] {
	/// A stored rule's field, named by ``RuleField`` rather than by a string.
	subscript(field: RuleField) -> PropertyListValue? {
		get { self[field.rawValue] }
		set { self[field.rawValue] = newValue }
	}
}
