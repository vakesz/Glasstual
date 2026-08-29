/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2015 - 2018 Codeux Software, LLC & respective contributors.
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

import Foundation

enum ChatFilterDestination: UInt {
	case unrestricted
	case channels
	case privateMessages
	case specificItems
}

enum ChatFilterAgeComparator: UInt {
	case none
	case lessThan
	case greaterThan
}

nonisolated struct ChatFilterEvent: OptionSet { // nonisolated: value
	let rawValue: UInt

	static let numeric = Self(rawValue: 1 << 0)
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

/** One filter rule.

 A main-actor model: the plugin holds its filters in an `NSArrayController` and
 the edit sheet binds to them by KVC key path, both of which are main-actor
 AppKit, and the engine reads them from main-actor plugin callbacks. */
@objc(TPI_ChatFilter)
@MainActor
class ChatFilter: NSObject, NSCopying, NSMutableCopying {
	fileprivate var ignoreContentStorage = false
	fileprivate var ignoreOperatorsStorage = true
	fileprivate var logMatchStorage = false
	fileprivate var limitedToMyselfStorage = false
	fileprivate var eventsStorage: ChatFilterEvent = .defaultMessages
	fileprivate var destinationStorage: ChatFilterDestination = .unrestricted
	fileprivate var ageComparatorStorage: ChatFilterAgeComparator = .greaterThan
	fileprivate var ageLimitStorage: UInt = 0
	fileprivate var actionFloodControlIntervalStorage: UInt = 0
	fileprivate var limitedToChannelIDsStorage: [String] = []
	fileprivate var limitedToClientIDsStorage: [String] = []
	fileprivate var eventNumericsStorage: [String] = []
	fileprivate var actionStorage = ""
	fileprivate var forwardDestinationStorage = ""
	fileprivate var matchStorage = ""
	fileprivate var notesStorage = ""
	fileprivate var senderMatchStorage = ""
	fileprivate var titleStorage = ""
	fileprivate var identifierStorage = ""
	fileprivate let commandCache = NSCache<NSString, NSNumber>()

	@objc dynamic var filterIgnoreContent: Bool {
		ignoreContentStorage
	}

	@objc dynamic var filterIgnoreOperators: Bool {
		ignoreOperatorsStorage
	}

	@objc dynamic var filterLogMatch: Bool {
		logMatchStorage
	}

	@objc dynamic var filterLimitedToMyself: Bool {
		limitedToMyselfStorage
	}

	@objc dynamic var filterEvents: UInt {
		eventsStorage.rawValue
	}

	@objc dynamic var filterLimitedToValue: UInt {
		destinationStorage.rawValue
	}

	@objc dynamic var filterAgeComparator: UInt {
		ageComparatorStorage.rawValue
	}

	@objc dynamic var filterAgeLimit: UInt {
		ageLimitStorage
	}

	@objc dynamic var filterActionFloodControlInterval: UInt {
		actionFloodControlIntervalStorage
	}

	@objc dynamic var filterLimitedToChannelsIDs: [String] {
		limitedToChannelIDsStorage
	}

	@objc dynamic var filterLimitedToClientsIDs: [String] {
		limitedToClientIDsStorage
	}

	@objc dynamic var filterEventsNumerics: [String] {
		eventNumericsStorage
	}

	@objc dynamic var filterAction: String {
		actionStorage
	}

	@objc dynamic var filterForwardToDestination: String {
		forwardDestinationStorage
	}

	@objc dynamic var filterMatch: String {
		matchStorage
	}

	@objc dynamic var filterNotes: String {
		notesStorage
	}

	@objc dynamic var filterSenderMatch: String {
		senderMatchStorage
	}

	@objc dynamic var filterTitle: String {
		titleStorage
	}

	@objc dynamic var uniqueIdentifier: String {
		identifierStorage
	}

	@objc dynamic var filterDescription: String {
		String(localized: .TPIChatFilterExtension.filterDescription(titleStorage))
	}

	override init() {
		super.init()
		populate(from: [:])
	}

	@objc(initWithDictionary:)
	init(dictionary: [String: Any]) {
		super.init()
		populate(from: dictionary)
	}

	@objc(initWithContentsOfPath:)
	convenience init?(contentsOfPath path: String) {
		self.init(contentsOf: URL(fileURLWithPath: path))
	}

	@objc(initWithContentsOfURL:)
	convenience init?(contentsOf url: URL) {
		guard let data = try? Data(contentsOf: url),
		      let propertyList = try? PropertyListSerialization.propertyList(from: data, format: nil),
		      let dictionary = propertyList as? [String: Any]
		else {
			return nil
		}
		self.init(dictionary: dictionary)
	}

	private func populate(from dictionary: [String: Any]) {
		ignoreContentStorage = bool(dictionary["filterIgnoreContent"])
		ignoreOperatorsStorage = optionalBool(dictionary["filterIgnoresOperators"]) ?? true
		limitedToMyselfStorage = bool(dictionary["filterLimitedToMyself"])
		logMatchStorage = bool(dictionary["filterLogMatch"])
		limitedToChannelIDsStorage = dictionary["filterLimitedToChannelsIDs"] as? [String] ?? []
		limitedToClientIDsStorage = dictionary["filterLimitedToClientsIDs"] as? [String] ?? []
		eventNumericsStorage = dictionary["filterEventsNumerics"] as? [String] ?? []
		actionStorage = string(dictionary["filterAction"])
		forwardDestinationStorage = string(dictionary["filterForwardToDestination"])
		matchStorage = string(dictionary["filterMatch"])
		notesStorage = string(dictionary["filterNotes"])
		senderMatchStorage = string(dictionary["filterSenderMatch"])
		titleStorage = string(dictionary["filterTitle"])
		identifierStorage = string(dictionary["uniqueIdentifier"])
		actionFloodControlIntervalStorage = uint(dictionary["filterActionFloodControlInterval"])
		destinationStorage = ChatFilterDestination(rawValue: uint(dictionary["filterLimitedToValue"])) ?? .unrestricted
		ageComparatorStorage = ChatFilterAgeComparator(rawValue: uint(dictionary["filterAgeComparator"])) ??
			.greaterThan
		ageLimitStorage = uint(dictionary["filterAgeLimit"])

		if let rawEvents = dictionary["filterEvents"] as? NSNumber {
			eventsStorage = ChatFilterEvent(rawValue: rawEvents.uintValue)
		} else {
			var events = ChatFilterEvent.defaultMessages
			if optionalBool(dictionary["filterCommandPRIVMSG"]) == false {
				events.remove(.plainTextMessage)
			}
			if optionalBool(dictionary["filterCommandPRIVMSG_ACTION"]) == false {
				events.remove(.actionMessage)
			}
			if bool(dictionary["filterCommandNOTICE"]) {
				events.insert(.noticeMessage)
			}
			eventsStorage = events
		}

		if identifierStorage.isEmpty {
			identifierStorage = UUID().uuidString
		}
	}

	var dictionaryValue: [String: Any] {
		let values: [String: Any] = [
			"filterCommandPRIVMSG": isEventTypeEnabled(.plainTextMessage),
			"filterCommandPRIVMSG_ACTION": isEventTypeEnabled(.actionMessage),
			"filterCommandNOTICE": isEventTypeEnabled(.noticeMessage),
			"filterLimitedToChannelsIDs": limitedToChannelIDsStorage,
			"filterLimitedToClientsIDs": limitedToClientIDsStorage,
			"filterEventsNumerics": eventNumericsStorage,
			"filterAction": actionStorage,
			"filterForwardToDestination": forwardDestinationStorage,
			"filterMatch": matchStorage,
			"filterNotes": notesStorage,
			"filterSenderMatch": senderMatchStorage,
			"filterTitle": titleStorage,
			"uniqueIdentifier": identifierStorage,
			"filterIgnoreContent": ignoreContentStorage,
			"filterIgnoresOperators": ignoreOperatorsStorage,
			"filterLimitedToMyself": limitedToMyselfStorage,
			"filterLogMatch": logMatchStorage,
			"filterActionFloodControlInterval": actionFloodControlIntervalStorage,
			"filterEvents": eventsStorage.rawValue,
			"filterLimitedToValue": destinationStorage.rawValue,
			"filterAgeComparator": ageComparatorStorage.rawValue,
			"filterAgeLimit": ageLimitStorage,
		]
		let defaults: [String: Any] = [
			"filterEvents": ChatFilterEvent.defaultMessages.rawValue,
			"filterIgnoreContent": false,
			"filterIgnoresOperators": true,
			"filterLimitedToMyself": false,
			"filterLogMatch": false,
			"filterLimitedToValue": ChatFilterDestination.unrestricted.rawValue,
			"filterAgeComparator": ChatFilterAgeComparator.greaterThan.rawValue,
		]
		return values.filter { key, value in
			guard let defaultValue = defaults[key] else { return true }
			return (value as? NSObject)?.isEqual(defaultValue) == false
		}
	}

	func copy(with _: NSZone? = nil) -> Any {
		ChatFilter(dictionary: dictionaryValue)
	}

	func mutableCopy(with _: NSZone? = nil) -> Any {
		MutableChatFilter(dictionary: dictionaryValue)
	}

	func isEventTypeEnabled(_ event: ChatFilterEvent) -> Bool {
		eventsStorage.contains(event)
	}

	@objc(isEventTypeEnabled:)
	func isEventTypeEnabled(rawValue: UInt) -> Bool {
		isEventTypeEnabled(ChatFilterEvent(rawValue: rawValue))
	}

	@objc func isCommandEnabled(_ command: String) -> Bool {
		if let cached = commandCache.object(forKey: command as NSString) {
			return cached.boolValue
		}
		let mappedEvents: [String: ChatFilterEvent] = [
			"JOIN": .userJoinedChannel, "PART": .userLeftChannel, "KICK": .userKickedFromChannel,
			"QUIT": .userDisconnected, "NICK": .userChangedNickname, "TOPIC": .channelTopicChanged,
			"MODE": .channelModeChanged, "332": .channelTopicReceived, "333": .channelTopicReceived,
			"324": .channelModeReceived,
		]
		let enabled = mappedEvents[command].map(isEventTypeEnabled) ?? eventNumericsStorage.contains(command)
		commandCache.setObject(NSNumber(value: enabled), forKey: command as NSString)
		return enabled
	}

	@objc(writeToURL:)
	func write(to url: URL) -> Bool {
		do {
			let data = try PropertyListSerialization.data(
				fromPropertyList: dictionaryValue,
				format: .binary,
				options: 0
			)
			try data.write(to: url, options: .atomic)
			return true
		} catch {
			NSLog("Chat Filter property-list write failed: %@", error.localizedDescription)
			return false
		}
	}

	fileprivate func purgeCommandCache() {
		commandCache.removeAllObjects()
	}

	private func string(_ value: Any?) -> String {
		value as? String ?? ""
	}

	private func bool(_ value: Any?) -> Bool {
		optionalBool(value) ?? false
	}

	private func optionalBool(_ value: Any?) -> Bool? {
		if let number = value as? NSNumber {
			return number.boolValue
		}
		return value as? Bool
	}

	private func uint(_ value: Any?) -> UInt {
		(value as? NSNumber)?.uintValue ?? value as? UInt ?? 0
	}
}

@objc(TPI_ChatFilterMutable)
final class MutableChatFilter: ChatFilter {
	@objc override dynamic var filterIgnoreContent: Bool {
		get { ignoreContentStorage }
		set { ignoreContentStorage = newValue }
	}

	@objc override dynamic var filterIgnoreOperators: Bool {
		get { ignoreOperatorsStorage }
		set { ignoreOperatorsStorage = newValue }
	}

	@objc override dynamic var filterLogMatch: Bool {
		get { logMatchStorage }
		set { logMatchStorage = newValue }
	}

	@objc override dynamic var filterLimitedToMyself: Bool {
		get { limitedToMyselfStorage }
		set { limitedToMyselfStorage = newValue }
	}

	@objc override dynamic var filterEvents: UInt {
		get { eventsStorage.rawValue }
		set { eventsStorage = ChatFilterEvent(rawValue: newValue); purgeCommandCache() }
	}

	@objc override dynamic var filterLimitedToValue: UInt {
		get { destinationStorage.rawValue }
		set { destinationStorage = ChatFilterDestination(rawValue: newValue) ?? .unrestricted }
	}

	@objc override dynamic var filterAgeComparator: UInt {
		get { ageComparatorStorage.rawValue }
		set { ageComparatorStorage = ChatFilterAgeComparator(rawValue: newValue) ?? .none }
	}

	@objc override dynamic var filterAgeLimit: UInt {
		get { ageLimitStorage }
		set { ageLimitStorage = newValue }
	}

	@objc override dynamic var filterActionFloodControlInterval: UInt {
		get { actionFloodControlIntervalStorage }
		set { actionFloodControlIntervalStorage = newValue }
	}

	@objc override dynamic var filterLimitedToChannelsIDs: [String] {
		get { limitedToChannelIDsStorage }
		set { limitedToChannelIDsStorage = newValue }
	}

	@objc override dynamic var filterLimitedToClientsIDs: [String] {
		get { limitedToClientIDsStorage }
		set { limitedToClientIDsStorage = newValue }
	}

	@objc override dynamic var filterEventsNumerics: [String] {
		get { eventNumericsStorage }
		set { eventNumericsStorage = newValue; purgeCommandCache() }
	}

	@objc override dynamic var filterAction: String {
		get { actionStorage }
		set { actionStorage = newValue }
	}

	@objc override dynamic var filterForwardToDestination: String {
		get { forwardDestinationStorage }
		set { forwardDestinationStorage = newValue }
	}

	@objc override dynamic var filterMatch: String {
		get { matchStorage }
		set { matchStorage = newValue }
	}

	@objc override dynamic var filterNotes: String {
		get { notesStorage }
		set { notesStorage = newValue }
	}

	@objc override dynamic var filterSenderMatch: String {
		get { senderMatchStorage }
		set { senderMatchStorage = newValue }
	}

	@objc override dynamic var filterTitle: String {
		get { titleStorage }
		set { titleStorage = newValue }
	}
}
