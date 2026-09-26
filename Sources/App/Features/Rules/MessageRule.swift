// Copyright (c) 2015 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation

nonisolated enum MessageRuleDestination: UInt, CaseIterable, Identifiable, Sendable {
	case unrestricted
	case channels
	case privateMessages
	case specificItems

	var id: Self {
		self
	}
}

nonisolated enum MessageRuleAgeComparator: UInt, CaseIterable, Identifiable, Sendable {
	case none
	case lessThan
	case greaterThan

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

/// One complete, independently editable message rule. The stored property list
/// names every field after the property it sets; everything above it works with
/// typed Swift state.
nonisolated struct MessageRule: Identifiable, Sendable {
	static let maximumDocumentBytes = 16 * 1024 * 1024

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
	var limitedSessionIDs: [String] = []
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
		ignoresContent = dictionary[.ignoresContent]?.boolean ?? false
		ignoresOperators = dictionary[.ignoresOperators]?.boolean ?? true
		isLimitedToMyself = dictionary[.limitedToMyself]?.boolean ?? false
		logsMatch = dictionary[.logsMatch]?.boolean ?? false
		limitedChannelIDs = dictionary[.limitedChannelIDs]?.stringArray ?? []
		limitedSessionIDs = dictionary[.limitedSessionIDs]?.stringArray ?? []
		additionalCommands = dictionary[.additionalCommands]?.stringArray ?? []
		action = dictionary[.action]?.string ?? ""
		forwardDestination = dictionary[.forwardDestination]?.string ?? ""
		match = dictionary[.match]?.string ?? ""
		notes = dictionary[.notes]?.string ?? ""
		senderMatch = dictionary[.senderMatch]?.string ?? ""
		title = dictionary[.title]?.string ?? ""
		id = dictionary[.uniqueIdentifier]?.string ?? ""
		actionFloodControlInterval = Self.uint(dictionary[.actionFloodControlInterval])
		destination = MessageRuleDestination(rawValue: Self.uint(dictionary[.destination])) ?? .unrestricted
		if let comparator = dictionary[.ageComparator] {
			ageComparator = MessageRuleAgeComparator(rawValue: Self.uint(comparator)) ?? .greaterThan
		}
		ageLimit = Self.uint(dictionary[.ageLimit])

		if let rawEvents = dictionary[.events]?.integer {
			events = MessageRuleEvent(rawValue: UInt(clamping: rawEvents))
		}

		if id.isEmpty {
			id = UUID().uuidString
		}
	}

	/// Reads one regular file under the import limit, holding sandbox access
	/// for the read. Cancellation prevents a dismissed pane from opening an editor.
	@concurrent
	static func read(from url: URL) async throws -> MessageRule {
		try Task.checkCancellation()
		let access = url.startAccessingSecurityScopedResource()
		defer {
			if access {
				url.stopAccessingSecurityScopedResource()
			}
		}
		let attributes = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
		guard attributes.isRegularFile == true else { throw CocoaError(.fileReadCorruptFile) }
		guard let size = attributes.fileSize, size <= maximumDocumentBytes else { throw CocoaError(.fileReadTooLarge) }
		let handle = try FileHandle(forReadingFrom: url)
		defer { try? handle.close() }
		let data = try handle.read(upToCount: maximumDocumentBytes + 1) ?? Data()
		guard data.count <= maximumDocumentBytes else { throw CocoaError(.fileReadTooLarge) }
		try Task.checkCancellation()
		let propertyList = try PropertyListSerialization.propertyList(from: data, format: nil)
		guard let dictionary = [String: PropertyListValue](propertyList: propertyList) else {
			throw CocoaError(.fileReadCorruptFile)
		}
		try Task.checkCancellation()
		return MessageRule(dictionary: dictionary)
	}

	var description: String {
		String(localized: .Rules.filterDescription(title))
	}

	/// A field sitting on its default is left out, so a stored rule re-encodes to
	/// exactly the dictionary it was read from.
	var dictionaryValue: [String: PropertyListValue] {
		let values: [RuleField: PropertyListValue] = [
			.uniqueIdentifier: .string(id),
			.title: .string(title),
			.match: .string(match),
			.senderMatch: .string(senderMatch),
			.notes: .string(notes),
			.action: .string(action),
			.forwardDestination: .string(forwardDestination),
			.additionalCommands: PropertyListValue(additionalCommands),
			.limitedChannelIDs: PropertyListValue(limitedChannelIDs),
			.limitedSessionIDs: PropertyListValue(limitedSessionIDs),
			.ignoresContent: .boolean(ignoresContent),
			.ignoresOperators: .boolean(ignoresOperators),
			.limitedToMyself: .boolean(isLimitedToMyself),
			.logsMatch: .boolean(logsMatch),
			.destination: .integer(Int(destination.rawValue)),
			.ageComparator: .integer(Int(ageComparator.rawValue)),
			.ageLimit: .integer(Int(ageLimit)),
			.actionFloodControlInterval: .integer(Int(actionFloodControlInterval)),
			.events: .integer(Int(events.rawValue)),
		]
		let defaults: [RuleField: PropertyListValue] = [
			.events: .integer(Int(MessageRuleEvent.defaultMessages.rawValue)),
			.ignoresContent: false,
			.ignoresOperators: true,
			.limitedToMyself: false,
			.logsMatch: false,
			.destination: .integer(Int(MessageRuleDestination.unrestricted.rawValue)),
			.ageComparator: .integer(Int(MessageRuleAgeComparator.greaterThan.rawValue)),
		]
		return values.reduce(into: [:]) { stored, entry in
			guard defaults[entry.key] != entry.value else { return }
			stored[entry.key.rawValue] = entry.value
		}
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
		return additionalCommands.contains(command)
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

	private static func uint(_ value: PropertyListValue?) -> UInt {
		value?.integer.map(UInt.init(clamping:)) ?? 0
	}
}
