/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\\__|\__,_|\__,_|_|
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

struct ChatFilterEvent: OptionSet {
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

@objc(TPI_ChatFilter)
class ChatFilter: XRPortablePropertyDict {
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
	fileprivate var defaultsStorage: [String: Any] = [:]
	fileprivate let commandCache = NSCache<NSString, NSNumber>()

	@objc var filterIgnoreContent: Bool {
		ignoreContentStorage
	}

	@objc var filterIgnoreOperators: Bool {
		ignoreOperatorsStorage
	}

	@objc var filterLogMatch: Bool {
		logMatchStorage
	}

	@objc var filterLimitedToMyself: Bool {
		limitedToMyselfStorage
	}

	@objc var filterEvents: UInt {
		eventsStorage.rawValue
	}

	@objc var filterLimitedToValue: UInt {
		destinationStorage.rawValue
	}

	@objc var filterAgeComparator: UInt {
		ageComparatorStorage.rawValue
	}

	@objc var filterAgeLimit: UInt {
		ageLimitStorage
	}

	@objc var filterActionFloodControlInterval: UInt {
		actionFloodControlIntervalStorage
	}

	@objc var filterLimitedToChannelsIDs: [String] {
		limitedToChannelIDsStorage
	}

	@objc var filterLimitedToClientsIDs: [String] {
		limitedToClientIDsStorage
	}

	@objc var filterEventsNumerics: [String] {
		eventNumericsStorage
	}

	@objc var filterAction: String {
		actionStorage
	}

	@objc var filterForwardToDestination: String {
		forwardDestinationStorage
	}

	@objc var filterMatch: String {
		matchStorage
	}

	@objc var filterNotes: String {
		notesStorage
	}

	@objc var filterSenderMatch: String {
		senderMatchStorage
	}

	@objc var filterTitle: String {
		titleStorage
	}

	@objc var uniqueIdentifier: String {
		identifierStorage
	}

	@objc var filterDescription: String {
		let format = Bundle(for: Self.self).localizedString(
			forKey: "dka-bx", value: "%@", table: "TPI_ChatFilterExtension"
		)
		return String(format: format, titleStorage)
	}

	override init() {
		super.init(dictionary: [:])
	}

	@objc(initWithDictionary:)
	override required init(dictionary: [String: Any]) {
		super.init(dictionary: dictionary)
	}

	required init?(coder _: NSCoder) {
		nil
	}

	@objc(initWithContentsOfPath:)
	convenience init?(contentsOfPath path: String) {
		self.init(contentsOf: URL(fileURLWithPath: path))
	}

	@objc(initWithContentsOfURL:)
	convenience init?(contentsOf url: URL) {
		guard let dictionary = NSDictionary(contentsOf: url) as? [String: Any] else { return nil }
		self.init(dictionary: dictionary)
	}

	override func populateDefaultsPreflight() {
		guard !initializedAsCopy else { return }
		defaultsStorage = [
			"filterEvents": ChatFilterEvent.defaultMessages.rawValue,
			"filterIgnoreContent": false,
			"filterIgnoresOperators": true,
			"filterLimitedToMyself": false,
			"filterLogMatch": false,
			"filterLimitedToValue": ChatFilterDestination.unrestricted.rawValue,
			"filterAgeComparator": ChatFilterAgeComparator.greaterThan.rawValue,
		]
	}

	override func populateDefaultsPostflight() {
		guard !initializedAsCopy else { return }
		if identifierStorage.isEmpty {
			identifierStorage = UUID().uuidString
		}
	}

	override func populateDictionaryValues(_ dictionary: [String: Any]) {
		let values = defaultsStorage.merging(dictionary) { _, new in new }
		ignoreContentStorage = values.bool(for: "filterIgnoreContent")
		ignoreOperatorsStorage = values.bool(for: "filterIgnoresOperators")
		limitedToMyselfStorage = values.bool(for: "filterLimitedToMyself")
		logMatchStorage = values.bool(for: "filterLogMatch")
		limitedToChannelIDsStorage = values["filterLimitedToChannelsIDs"] as? [String] ?? []
		limitedToClientIDsStorage = values["filterLimitedToClientsIDs"] as? [String] ?? []
		eventNumericsStorage = values["filterEventsNumerics"] as? [String] ?? []
		actionStorage = values.string(for: "filterAction")
		forwardDestinationStorage = values.string(for: "filterForwardToDestination")
		matchStorage = values.string(for: "filterMatch")
		notesStorage = values.string(for: "filterNotes")
		senderMatchStorage = values.string(for: "filterSenderMatch")
		titleStorage = values.string(for: "filterTitle")
		identifierStorage = values.string(for: "uniqueIdentifier")
		actionFloodControlIntervalStorage = values.uint(for: "filterActionFloodControlInterval")
		destinationStorage = ChatFilterDestination(rawValue: values.uint(for: "filterLimitedToValue")) ?? .unrestricted
		ageComparatorStorage = ChatFilterAgeComparator(rawValue: values.uint(for: "filterAgeComparator")) ??
			.greaterThan
		ageLimitStorage = values.uint(for: "filterAgeLimit")

		if let eventValue = dictionary["filterEvents"] as? NSNumber {
			eventsStorage = ChatFilterEvent(rawValue: eventValue.uintValue)
		} else {
			var events = ChatFilterEvent.defaultMessages
			if values.optionalBool(for: "filterCommandPRIVMSG") == false {
				events.remove(.plainTextMessage)
			}
			if values.optionalBool(for: "filterCommandPRIVMSG_ACTION") == false {
				events.remove(.actionMessage)
			}
			if values.bool(for: "filterCommandNOTICE") {
				events.insert(.noticeMessage)
			}
			eventsStorage = events
		}
	}

	override func dictionaryValue(for target: XRPortablePropertyDictTarget) -> [String: Any] {
		let result: [String: Any] = [
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
		guard target != .copy, target != .mutableCopy else { return result }
		return (result as NSDictionary).removingDefaults(defaultsStorage) as! [String: Any]
	}

	override func copy(asMutable mutableCopy: Bool, uniquing: Bool) -> Any {
		let copy = super.copy(asMutable: mutableCopy, uniquing: uniquing) as! ChatFilter
		copy.defaultsStorage = defaultsStorage
		return copy
	}

	override var mutableClass: XRPortablePropertyDict {
		unsafeBitCast(MutableChatFilter.self, to: XRPortablePropertyDict.self)
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

	@objc(writeToPath:)
	func write(toPath path: String) -> Bool {
		write(to: URL(fileURLWithPath: path))
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
}

@objc(TPI_ChatFilterMutable)
final class MutableChatFilter: ChatFilter {
	override class var isMutable: Bool {
		true
	}

	override var immutableClass: XRPortablePropertyDict {
		unsafeBitCast(ChatFilter.self, to: XRPortablePropertyDict.self)
	}

	@objc override var filterIgnoreContent: Bool {
		get { ignoreContentStorage }
		set { ignoreContentStorage = newValue }
	}

	@objc override var filterIgnoreOperators: Bool {
		get { ignoreOperatorsStorage }
		set { ignoreOperatorsStorage = newValue }
	}

	@objc override var filterLogMatch: Bool {
		get { logMatchStorage }
		set { logMatchStorage = newValue }
	}

	@objc override var filterLimitedToMyself: Bool {
		get { limitedToMyselfStorage }
		set { limitedToMyselfStorage = newValue }
	}

	@objc override var filterEvents: UInt {
		get { eventsStorage.rawValue }
		set {
			eventsStorage = ChatFilterEvent(rawValue: newValue)
			purgeCommandCache()
		}
	}

	@objc override var filterLimitedToValue: UInt {
		get { destinationStorage.rawValue }
		set { destinationStorage = ChatFilterDestination(rawValue: newValue) ?? .unrestricted }
	}

	@objc override var filterAgeComparator: UInt {
		get { ageComparatorStorage.rawValue }
		set { ageComparatorStorage = ChatFilterAgeComparator(rawValue: newValue) ?? .none }
	}

	@objc override var filterAgeLimit: UInt {
		get { ageLimitStorage }
		set { ageLimitStorage = newValue }
	}

	@objc override var filterActionFloodControlInterval: UInt {
		get { actionFloodControlIntervalStorage }
		set { actionFloodControlIntervalStorage = newValue }
	}

	@objc override var filterLimitedToChannelsIDs: [String] {
		get { limitedToChannelIDsStorage }
		set { limitedToChannelIDsStorage = newValue }
	}

	@objc override var filterLimitedToClientsIDs: [String] {
		get { limitedToClientIDsStorage }
		set { limitedToClientIDsStorage = newValue }
	}

	@objc override var filterEventsNumerics: [String] {
		get { eventNumericsStorage }
		set {
			eventNumericsStorage = newValue
			purgeCommandCache()
		}
	}

	@objc override var filterAction: String {
		get { actionStorage }
		set { actionStorage = newValue }
	}

	@objc override var filterForwardToDestination: String {
		get { forwardDestinationStorage }
		set { forwardDestinationStorage = newValue }
	}

	@objc override var filterMatch: String {
		get { matchStorage }
		set { matchStorage = newValue }
	}

	@objc override var filterNotes: String {
		get { notesStorage }
		set { notesStorage = newValue }
	}

	@objc override var filterSenderMatch: String {
		get { senderMatchStorage }
		set { senderMatchStorage = newValue }
	}

	@objc override var filterTitle: String {
		get { titleStorage }
		set { titleStorage = newValue }
	}
}

private extension [String: Any] {
	func bool(for key: String) -> Bool {
		(self[key] as? NSNumber)?.boolValue ?? false
	}

	func optionalBool(for key: String) -> Bool? {
		(self[key] as? NSNumber)?.boolValue
	}

	func uint(for key: String) -> UInt {
		(self[key] as? NSNumber)?.uintValue ?? 0
	}

	func string(for key: String) -> String {
		self[key] as? String ?? ""
	}
}
