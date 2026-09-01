/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2015 - 2026 Codeux Software, LLC & respective contributors.
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

enum ChatFilterDestination: UInt, CaseIterable, Identifiable {
	case unrestricted
	case channels
	case privateMessages
	case specificItems

	var id: Self {
		self
	}
}

enum ChatFilterAgeComparator: UInt, CaseIterable, Identifiable {
	case none
	case lessThan
	case greaterThan

	var id: Self {
		self
	}
}

struct ChatFilterEvent: OptionSet {
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

/// A complete, independently editable filter rule.
///
/// Persistence keeps the legacy property-list spelling so existing filters and
/// exported files remain compatible; the rest of the plugin works with typed
/// Swift state and never reaches this model through KVC or Cocoa bindings.
struct ChatFilter: Identifiable {
	var ignoresContent = false
	var ignoresOperators = true
	var logsMatch = false
	var isLimitedToMyself = false
	var events: ChatFilterEvent = .defaultMessages
	var destination: ChatFilterDestination = .unrestricted
	var ageComparator: ChatFilterAgeComparator = .greaterThan
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
		destination = ChatFilterDestination(rawValue: Self.uint(dictionary["filterLimitedToValue"])) ?? .unrestricted
		ageComparator = ChatFilterAgeComparator(rawValue: Self.uint(dictionary["filterAgeComparator"])) ?? .greaterThan
		ageLimit = Self.uint(dictionary["filterAgeLimit"])

		if let rawEvents = dictionary["filterEvents"]?.integer {
			events = ChatFilterEvent(rawValue: UInt(clamping: rawEvents))
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
		String(localized: .TPIChatFilterExtension.filterDescription(title))
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
			"filterEvents": .integer(Int(ChatFilterEvent.defaultMessages.rawValue)),
			"filterIgnoreContent": false,
			"filterIgnoresOperators": true,
			"filterLimitedToMyself": false,
			"filterLogMatch": false,
			"filterLimitedToValue": .integer(Int(ChatFilterDestination.unrestricted.rawValue)),
			"filterAgeComparator": .integer(Int(ChatFilterAgeComparator.greaterThan.rawValue)),
		]
		return values.filter { key, value in defaults[key] != value }
	}

	func isEventEnabled(_ event: ChatFilterEvent) -> Bool {
		events.contains(event)
	}

	func isCommandEnabled(_ command: String) -> Bool {
		let mappedEvents: [String: ChatFilterEvent] = [
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
			fromPropertyList: dictionaryValue,
			format: .binary,
			options: 0
		)
	}

	private mutating func migrateLegacyEvents(from dictionary: [String: PropertyListValue]) {
		var migratedEvents = ChatFilterEvent.defaultMessages
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
