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

import CocoaExtensions
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

	var filterIgnoreContent: Bool {
		ignoreContentStorage
	}

	var filterIgnoreOperators: Bool {
		ignoreOperatorsStorage
	}

	var filterLogMatch: Bool {
		logMatchStorage
	}

	var filterLimitedToMyself: Bool {
		limitedToMyselfStorage
	}

	var filterEvents: UInt {
		eventsStorage.rawValue
	}

	var filterLimitedToValue: UInt {
		destinationStorage.rawValue
	}

	var filterAgeComparator: UInt {
		ageComparatorStorage.rawValue
	}

	var filterAgeLimit: UInt {
		ageLimitStorage
	}

	var filterActionFloodControlInterval: UInt {
		actionFloodControlIntervalStorage
	}

	var filterLimitedToChannelsIDs: [String] {
		limitedToChannelIDsStorage
	}

	var filterLimitedToClientsIDs: [String] {
		limitedToClientIDsStorage
	}

	var filterEventsNumerics: [String] {
		eventNumericsStorage
	}

	var filterAction: String {
		actionStorage
	}

	var filterForwardToDestination: String {
		forwardDestinationStorage
	}

	var filterMatch: String {
		matchStorage
	}

	var filterNotes: String {
		notesStorage
	}

	var filterSenderMatch: String {
		senderMatchStorage
	}

	var filterTitle: String {
		titleStorage
	}

	var uniqueIdentifier: String {
		identifierStorage
	}

	@objc dynamic var filterDescription: String {
		String(localized: .TPIChatFilterExtension.filterDescription(titleStorage))
	}

	override init() {
		super.init()
		populate(from: [:])
	}

	init(dictionary: [String: PropertyListValue]) {
		super.init()
		populate(from: dictionary)
	}

	convenience init?(contentsOfPath path: String) {
		self.init(contentsOf: URL(fileURLWithPath: path))
	}

	convenience init?(contentsOf url: URL) {
		guard let data = try? Data(contentsOf: url),
		      let propertyList = try? PropertyListSerialization.propertyList(from: data, format: nil),
		      let dictionary = [String: PropertyListValue](propertyList: propertyList)
		else {
			return nil
		}
		self.init(dictionary: dictionary)
	}

	private func populate(from dictionary: [String: PropertyListValue]) {
		ignoreContentStorage = bool(dictionary["filterIgnoreContent"])
		ignoreOperatorsStorage = optionalBool(dictionary["filterIgnoresOperators"]) ?? true
		limitedToMyselfStorage = bool(dictionary["filterLimitedToMyself"])
		logMatchStorage = bool(dictionary["filterLogMatch"])
		limitedToChannelIDsStorage = dictionary["filterLimitedToChannelsIDs"]?.stringArray ?? []
		limitedToClientIDsStorage = dictionary["filterLimitedToClientsIDs"]?.stringArray ?? []
		eventNumericsStorage = dictionary["filterEventsNumerics"]?.stringArray ?? []
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

		if let rawEvents = dictionary["filterEvents"]?.integer {
			eventsStorage = ChatFilterEvent(rawValue: UInt(clamping: rawEvents))
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

	var dictionaryValue: [String: PropertyListValue] {
		let values: [String: PropertyListValue] = [
			"filterCommandPRIVMSG": .boolean(isEventTypeEnabled(.plainTextMessage)),
			"filterCommandPRIVMSG_ACTION": .boolean(isEventTypeEnabled(.actionMessage)),
			"filterCommandNOTICE": .boolean(isEventTypeEnabled(.noticeMessage)),
			"filterLimitedToChannelsIDs": PropertyListValue(limitedToChannelIDsStorage),
			"filterLimitedToClientsIDs": PropertyListValue(limitedToClientIDsStorage),
			"filterEventsNumerics": PropertyListValue(eventNumericsStorage),
			"filterAction": .string(actionStorage),
			"filterForwardToDestination": .string(forwardDestinationStorage),
			"filterMatch": .string(matchStorage),
			"filterNotes": .string(notesStorage),
			"filterSenderMatch": .string(senderMatchStorage),
			"filterTitle": .string(titleStorage),
			"uniqueIdentifier": .string(identifierStorage),
			"filterIgnoreContent": .boolean(ignoreContentStorage),
			"filterIgnoresOperators": .boolean(ignoreOperatorsStorage),
			"filterLimitedToMyself": .boolean(limitedToMyselfStorage),
			"filterLogMatch": .boolean(logMatchStorage),
			"filterActionFloodControlInterval": .integer(Int(actionFloodControlIntervalStorage)),
			"filterEvents": .integer(Int(eventsStorage.rawValue)),
			"filterLimitedToValue": .integer(Int(destinationStorage.rawValue)),
			"filterAgeComparator": .integer(Int(ageComparatorStorage.rawValue)),
			"filterAgeLimit": .integer(Int(ageLimitStorage)),
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
		return values.filter { key, value in
			defaults[key] != value
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

	func isEventTypeEnabled(rawValue: UInt) -> Bool {
		isEventTypeEnabled(ChatFilterEvent(rawValue: rawValue))
	}

	func isCommandEnabled(_ command: String) -> Bool {
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

	private func string(_ value: PropertyListValue?) -> String {
		value?.string ?? ""
	}

	private func bool(_ value: PropertyListValue?) -> Bool {
		value?.boolean ?? false
	}

	private func optionalBool(_ value: PropertyListValue?) -> Bool? {
		value?.boolean
	}

	private func uint(_ value: PropertyListValue?) -> UInt {
		value?.integer.map(UInt.init(clamping:)) ?? 0
	}
}

final class MutableChatFilter: ChatFilter {
	override var filterIgnoreContent: Bool {
		get { ignoreContentStorage }
		set { ignoreContentStorage = newValue }
	}

	override var filterIgnoreOperators: Bool {
		get { ignoreOperatorsStorage }
		set { ignoreOperatorsStorage = newValue }
	}

	override var filterLogMatch: Bool {
		get { logMatchStorage }
		set { logMatchStorage = newValue }
	}

	override var filterLimitedToMyself: Bool {
		get { limitedToMyselfStorage }
		set { limitedToMyselfStorage = newValue }
	}

	override var filterEvents: UInt {
		get { eventsStorage.rawValue }
		set { eventsStorage = ChatFilterEvent(rawValue: newValue); purgeCommandCache() }
	}

	override var filterLimitedToValue: UInt {
		get { destinationStorage.rawValue }
		set { destinationStorage = ChatFilterDestination(rawValue: newValue) ?? .unrestricted }
	}

	override var filterAgeComparator: UInt {
		get { ageComparatorStorage.rawValue }
		set { ageComparatorStorage = ChatFilterAgeComparator(rawValue: newValue) ?? .none }
	}

	override var filterAgeLimit: UInt {
		get { ageLimitStorage }
		set { ageLimitStorage = newValue }
	}

	override var filterActionFloodControlInterval: UInt {
		get { actionFloodControlIntervalStorage }
		set { actionFloodControlIntervalStorage = newValue }
	}

	override var filterLimitedToChannelsIDs: [String] {
		get { limitedToChannelIDsStorage }
		set { limitedToChannelIDsStorage = newValue }
	}

	override var filterLimitedToClientsIDs: [String] {
		get { limitedToClientIDsStorage }
		set { limitedToClientIDsStorage = newValue }
	}

	override var filterEventsNumerics: [String] {
		get { eventNumericsStorage }
		set { eventNumericsStorage = newValue; purgeCommandCache() }
	}

	override var filterAction: String {
		get { actionStorage }
		set { actionStorage = newValue }
	}

	override var filterForwardToDestination: String {
		get { forwardDestinationStorage }
		set { forwardDestinationStorage = newValue }
	}

	override var filterMatch: String {
		get { matchStorage }
		set { matchStorage = newValue }
	}

	override var filterNotes: String {
		get { notesStorage }
		set { notesStorage = newValue }
	}

	override var filterSenderMatch: String {
		get { senderMatchStorage }
		set { senderMatchStorage = newValue }
	}

	override var filterTitle: String {
		get { titleStorage }
		set { titleStorage = newValue }
	}
}
