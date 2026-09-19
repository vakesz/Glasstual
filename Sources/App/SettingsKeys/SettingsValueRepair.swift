// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation

/** What a stored payload has to look like, and what can be salvaged when it
 does not.

 The two payloads with fields of their own, nickname colour overrides and
 message rules, are checked and repaired here rather than at the readers, so a
 permissive reader cannot quietly drop an entry it did not understand. */
nonisolated enum SettingsValueRepair {
	static func nicknameColors(_ value: PropertyListValue) -> Bool {
		guard let overrides = value.dictionary else { return false }
		return overrides.values.allSatisfy { value in
			if let data = value.data {
				return SettingsColor.settingValue(from: data) != nil
			}
			guard let components = value.dictionary,
			      let color = NicknameColorComponents(stored: components.compactMapValues(\.double))
			else { return false }
			return [color.red, color.green, color.blue, color.alpha]
				.allSatisfy { $0.isFinite && (0 ... 1).contains($0) }
		}
	}

	static func messageRules(_ value: PropertyListValue) -> Bool {
		guard let rules = value.array else { return false }
		var identifiers: Set<String> = []
		for rule in rules {
			guard let dictionary = rule.dictionary,
			      let identifier = dictionary[.uniqueIdentifier]?.string, !identifier.isEmpty,
			      identifiers.insert(identifier).inserted,
			      dictionary.allSatisfy({ repairedRuleField($0.key, $0.value) == $0.value }) else { return false }
		}
		return true
	}

	/// The title and action of every message rule in a stored rule list, by
	/// identifier.
	static func messageRuleActions(in value: PropertyListValue?) -> [String: (title: String, action: String)] {
		var actions: [String: (title: String, action: String)] = [:]
		for rule in value?.array ?? [] {
			guard let dictionary = rule.dictionary, let identifier = dictionary[.uniqueIdentifier]?.string else {
				continue
			}
			actions[identifier] = (
				title: dictionary[.title]?.string ?? "",
				action: dictionary[.action]?.string ?? ""
			)
		}
		return actions
	}

	/** Payloads that can lose one bad field instead of a whole rule.

	 The generic repair drops a collection element the declaration refuses. A
	 message rule is a dictionary of independent fields, so one field a hand edit
	 spoiled costs that field — the engine reads a missing field as its
	 default — and a rule without a usable identifier is given a
	 new one, which is what loading one does anyway. */
	static let repairs: [String: @Sendable (PropertyListValue) -> PropertyListValue] = [
		SettingsKeys.Rules.messageRules.name: repairedMessageRules,
	]

	private static func repairedMessageRules(_ value: PropertyListValue) -> PropertyListValue {
		guard let rules = value.array else { return value }
		var identifiers: Set<String> = []
		return .array(rules.map { rule in
			guard let dictionary = rule.dictionary else { return rule }
			var repaired: [String: PropertyListValue] = [:]
			for (name, field) in dictionary {
				repaired[name] = repairedRuleField(name, field)
			}
			if let identifier = repaired[.uniqueIdentifier]?.string, !identifier.isEmpty,
			   identifiers.insert(identifier).inserted
			{
				return .dictionary(repaired)
			}
			let identifier = UUID().uuidString
			identifiers.insert(identifier)
			repaired[.uniqueIdentifier] = .string(identifier)
			return .dictionary(repaired)
		})
	}

	/** The value a rule may keep for one field, or `nil` when the field has to go.

	 A field this build does not know is kept as it is: a newer build may have
	 written it, and the engine reads rules by the names it knows. */
	private static func repairedRuleField(_ name: String, _ value: PropertyListValue) -> PropertyListValue? {
		switch RuleField(rawValue: name) {
		case .uniqueIdentifier, .action, .forwardDestination, .match, .notes, .senderMatch, .title:
			return value.string == nil ? nil : value
		case .limitedChannelIDs, .limitedSessionIDs, .additionalCommands:
			return value.stringArray == nil ? nil : value
		case .ignoresContent, .ignoresOperators, .limitedToMyself, .logsMatch:
			return value.boolean == nil ? nil : value
		case .destination:
			return integer(value, in: 0 ... 3)
		case .ageComparator:
			return integer(value, in: 0 ... 2)
		case .events:
			// Bits outside the known events mean nothing to the engine, so a
			// repair clears them rather than losing the events that are known.
			guard case let .integer(number) = value, number >= 0 else { return nil }
			return .integer(number & knownRuleEvents)
		case .ageLimit, .actionFloodControlInterval:
			return integer(value, in: 0 ... Int.max)
		case nil:
			return value
		}
	}

	/// Bits 1 through 12: plain text through channel mode changes.
	private static let knownRuleEvents = 8190

	private static func integer(_ value: PropertyListValue, in range: ClosedRange<Int>) -> PropertyListValue? {
		guard case let .integer(number) = value, range.contains(number) else { return nil }
		return value
	}
}
