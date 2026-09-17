// Copyright (c) 2015 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation

enum MessageRuleDestination: UInt, CaseIterable, Identifiable {
	case unrestricted
	case channels
	case privateMessages
	case specificItems

	var id: Self {
		self
	}
}

enum MessageRuleAgeComparator: UInt, CaseIterable, Identifiable {
	case none
	case lessThan
	case greaterThan

	var id: Self {
		self
	}
}

struct MessageRuleEvent: OptionSet {
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

	static let defaultMessages: Self = [.plainTextMessage, .actionMessage]
}

/// One complete, independently editable message rule.
///
/// Persistence keeps the property-list spelling the rules were stored under
/// when they belonged to a bundled extension, so a user's rules and exported
/// files still read; everything above it works with typed Swift state.
struct MessageRule: Identifiable {
	var ignoresContent = false
	var ignoresOperators = true
	var logsMatch = false
	var isLimitedToMyself = false
	var events: MessageRuleEvent = .defaultMessages
	var destination: MessageRuleDestination = .unrestricted
	var ageComparator: MessageRuleAgeComparator = .greaterThan
	var ageLimit: UInt = 0
	var actionFloodControlInterval: UInt = 0
	var limitedChannelIDs: [String] = []
	var limitedClientIDs: [String] = []
	var additionalCommands: [String] = []
	var action = ""
	var forwardDestination = ""
	var match = ""
	var notes = ""
	var senderMatch = ""
	var title = ""
	var id = UUID().uuidString

	init() {}

	init(dictionary: [String: PropertyListValue]) {
		ignoresContent = dictionary["filterIgnoreContent"]?.boolean ?? false
		ignoresOperators = dictionary["filterIgnoresOperators"]?.boolean ?? true
		isLimitedToMyself = dictionary["filterLimitedToMyself"]?.boolean ?? false
		logsMatch = dictionary["filterLogMatch"]?.boolean ?? false
		limitedChannelIDs = dictionary["filterLimitedToChannelsIDs"]?.stringArray ?? []
		limitedClientIDs = dictionary["filterLimitedToClientsIDs"]?.stringArray ?? []
		additionalCommands = dictionary["filterEventsNumerics"]?.stringArray ?? []
		action = dictionary["filterAction"]?.string ?? ""
		forwardDestination = dictionary["filterForwardToDestination"]?.string ?? ""
		match = dictionary["filterMatch"]?.string ?? ""
		notes = dictionary["filterNotes"]?.string ?? ""
		senderMatch = dictionary["filterSenderMatch"]?.string ?? ""
		title = dictionary["filterTitle"]?.string ?? ""
		id = dictionary["uniqueIdentifier"]?.string ?? ""
		actionFloodControlInterval = Self.uint(dictionary["filterActionFloodControlInterval"])
		destination = MessageRuleDestination(rawValue: Self.uint(dictionary["filterLimitedToValue"])) ?? .unrestricted
		if let comparator = dictionary["filterAgeComparator"] {
			ageComparator = MessageRuleAgeComparator(rawValue: Self.uint(comparator)) ?? .greaterThan
		}
		ageLimit = Self.uint(dictionary["filterAgeLimit"])

		if let rawEvents = dictionary["filterEvents"]?.integer {
			events = MessageRuleEvent(rawValue: UInt(clamping: rawEvents))
		} else {
			migrateLegacyEvents(from: dictionary)
		}

		if id.isEmpty {
			id = UUID().uuidString
		}
	}

	init(contentsOf url: URL) throws {
		let data = try Data(contentsOf: url)
		let propertyList = try PropertyListSerialization.propertyList(from: data, format: nil)
		guard let dictionary = [String: PropertyListValue](propertyList: propertyList) else {
			throw CocoaError(.fileReadCorruptFile)
		}
		self.init(dictionary: dictionary)
	}

	var description: String {
		String(localized: .Rules.filterDescription(title))
	}

	var dictionaryValue: [String: PropertyListValue] {
		let values: [String: PropertyListValue] = [
			"filterCommandPRIVMSG": .boolean(isEventEnabled(.plainTextMessage)),
			"filterCommandPRIVMSG_ACTION": .boolean(isEventEnabled(.actionMessage)),
			"filterCommandNOTICE": .boolean(isEventEnabled(.noticeMessage)),
			"filterLimitedToChannelsIDs": PropertyListValue(limitedChannelIDs),
			"filterLimitedToClientsIDs": PropertyListValue(limitedClientIDs),
			"filterEventsNumerics": PropertyListValue(additionalCommands),
			"filterAction": .string(action),
			"filterForwardToDestination": .string(forwardDestination),
			"filterMatch": .string(match),
			"filterNotes": .string(notes),
			"filterSenderMatch": .string(senderMatch),
			"filterTitle": .string(title),
			"uniqueIdentifier": .string(id),
			"filterIgnoreContent": .boolean(ignoresContent),
			"filterIgnoresOperators": .boolean(ignoresOperators),
			"filterLimitedToMyself": .boolean(isLimitedToMyself),
			"filterLogMatch": .boolean(logsMatch),
			"filterActionFloodControlInterval": .integer(Int(actionFloodControlInterval)),
			"filterEvents": .integer(Int(events.rawValue)),
			"filterLimitedToValue": .integer(Int(destination.rawValue)),
			"filterAgeComparator": .integer(Int(ageComparator.rawValue)),
			"filterAgeLimit": .integer(Int(ageLimit)),
		]
		let defaults: [String: PropertyListValue] = [
			"filterEvents": .integer(Int(MessageRuleEvent.defaultMessages.rawValue)),
			"filterIgnoreContent": false,
			"filterIgnoresOperators": true,
			"filterLimitedToMyself": false,
			"filterLogMatch": false,
			"filterLimitedToValue": .integer(Int(MessageRuleDestination.unrestricted.rawValue)),
			"filterAgeComparator": .integer(Int(MessageRuleAgeComparator.greaterThan.rawValue)),
		]
		return values.filter { key, value in defaults[key] != value }
	}

	func isEventEnabled(_ event: MessageRuleEvent) -> Bool {
		events.contains(event)
	}

	func isCommandEnabled(_ command: String) -> Bool {
		let mappedEvents: [String: MessageRuleEvent] = [
			"JOIN": .userJoinedChannel, "PART": .userLeftChannel, "KICK": .userKickedFromChannel,
			"QUIT": .userDisconnected, "NICK": .userChangedNickname, "TOPIC": .channelTopicChanged,
			"MODE": .channelModeChanged, "332": .channelTopicReceived, "333": .channelTopicReceived,
			"324": .channelModeReceived,
		]
		if let event = mappedEvents[command] {
			return isEventEnabled(event)
		}
		if additionalCommands.contains(command) {
			return true
		}

		/* The former editor stored 001 as "1". Accept that legacy spelling
		 while new edits use the three-digit command IRC sends on the wire. */
		guard command.count == 3, command.allSatisfy(\.isNumber), let numeric = Int(command) else {
			return false
		}
		return additionalCommands.contains(String(numeric))
	}

	func write(to url: URL) throws {
		try propertyListData().write(to: url, options: .atomic)
	}

	func propertyListData() throws -> Data {
		try PropertyListSerialization.data(
			fromPropertyList: dictionaryValue.propertyListObject,
			format: .binary,
			options: 0
		)
	}

	private mutating func migrateLegacyEvents(from dictionary: [String: PropertyListValue]) {
		var migratedEvents = MessageRuleEvent.defaultMessages
		if dictionary["filterCommandPRIVMSG"]?.boolean == false {
			migratedEvents.remove(.plainTextMessage)
		}
		if dictionary["filterCommandPRIVMSG_ACTION"]?.boolean == false {
			migratedEvents.remove(.actionMessage)
		}
		if dictionary["filterCommandNOTICE"]?.boolean == true {
			migratedEvents.insert(.noticeMessage)
		}
		events = migratedEvents
	}

	private static func uint(_ value: PropertyListValue?) -> UInt {
		value?.integer.map(UInt.init(clamping:)) ?? 0
	}
}
