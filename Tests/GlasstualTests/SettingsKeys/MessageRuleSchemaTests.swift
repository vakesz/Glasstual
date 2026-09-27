// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
@testable import Glasstual
import Testing

@Suite("Message rule settings schema")
struct MessageRuleSchemaTests {
	@Test("Every destination survives settings validation", arguments: MessageRuleDestination.allCases)
	func destinationsAreAccepted(_ destination: MessageRuleDestination) {
		let value = rule(with: .destination, value: .integer(Int(destination.rawValue)))
		#expect(SettingsKeys.coerce(value, forKey: keyName) == value)
		#expect(SettingsKeys.salvage(value, forKey: keyName) == value)
	}

	@Test("Every age comparator survives settings validation", arguments: MessageRuleAgeComparator.allCases)
	func ageComparatorsAreAccepted(_ comparator: MessageRuleAgeComparator) {
		let value = rule(with: .ageComparator, value: .integer(Int(comparator.rawValue)))
		#expect(SettingsKeys.coerce(value, forKey: keyName) == value)
		#expect(SettingsKeys.salvage(value, forKey: keyName) == value)
	}

	@Test("Every event survives settings validation", arguments: [
		MessageRuleEvent.plainTextMessage, .actionMessage, .noticeMessage, .userJoinedChannel,
		.userLeftChannel, .userKickedFromChannel, .userDisconnected, .userChangedNickname,
		.channelTopicReceived, .channelTopicChanged, .channelModeReceived, .channelModeChanged,
	])
	func eventsAreAccepted(_ event: MessageRuleEvent) {
		let value = rule(with: .events, value: .integer(Int(event.rawValue)))
		#expect(SettingsKeys.coerce(value, forKey: keyName) == value)
		#expect(SettingsKeys.salvage(value, forKey: keyName) == value)
	}

	@Test("The complete event mask preserves its stored bits")
	func completeEventMaskKeepsItsStorageContract() {
		#expect(MessageRuleEvent.all.rawValue == 8190)
		let value = rule(with: .events, value: .integer(8190))
		#expect(SettingsKeys.coerce(value, forKey: keyName) == value)
		#expect(SettingsKeys.salvage(value, forKey: keyName) == value)
	}

	@Test("Repair removes unknown event bits while keeping every known event")
	func unknownEventBitsAreRemoved() {
		let value = rule(with: .events, value: .integer(8190 | 1 << 20))
		#expect(SettingsKeys.coerce(value, forKey: keyName) == nil)
		#expect(SettingsKeys.salvage(value, forKey: keyName) == rule(with: .events, value: .integer(8190)))
	}

	@Test("Unknown enumeration cases are removed", arguments: [RuleField.destination, .ageComparator])
	func unknownEnumerationCasesAreRemoved(_ field: RuleField) {
		let value = rule(with: field, value: .integer(Int.max))
		#expect(SettingsKeys.coerce(value, forKey: keyName) == nil)
		#expect(SettingsKeys.salvage(value, forKey: keyName) == rule(with: field, value: nil))
	}

	@Test("Rule choices require nonnegative stored integers", arguments:
		[RuleField.destination, .ageComparator, .events],
		[PropertyListValue.integer(-1), .string("1"), .double(1), .boolean(true)])
	func invalidRepresentationsAreRemoved(_ field: RuleField, _ representation: PropertyListValue) {
		let value = rule(with: field, value: representation)
		#expect(SettingsKeys.coerce(value, forKey: keyName) == nil)
		#expect(SettingsKeys.salvage(value, forKey: keyName) == rule(with: field, value: nil))
	}

	private var keyName: String {
		SettingsKeys.Rules.messageRules.name
	}

	private func rule(with field: RuleField, value: PropertyListValue?) -> PropertyListValue {
		var dictionary: [String: PropertyListValue] = [:]
		dictionary[.uniqueIdentifier] = "rule"
		dictionary[field] = value
		return .array([.dictionary(dictionary)])
	}
}
