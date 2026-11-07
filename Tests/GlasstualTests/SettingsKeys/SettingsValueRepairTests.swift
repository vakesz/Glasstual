// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation
@testable import Glasstual
import Testing

/// What a hand-edited message rule or nickname colour keeps, loses and is given.
struct SettingsValueRepairTests {
	private typealias Fields = [String: PropertyListValue]

	private func repaired(_ rules: [Fields]) throws -> [Fields] {
		let repair = try #require(SettingsValueRepair.repairs[SettingsKeys.Rules.messageRules.name])
		let result = repair(.array(rules.map { .dictionary($0) }))

		return try #require(result.array).map { try #require($0.dictionary) }
	}

	private func rule(_ extra: Fields = [:], id: String = "rule-1") -> Fields {
		var fields: Fields = ["uniqueIdentifier": .string(id)]
		fields.merge(extra) { _, new in new }

		return fields
	}

	// MARK: - Fields

	@Test("A field of the wrong type costs the field and not the rule")
	func wrongTypeDropsTheField() throws {
		let result = try repaired([rule([
			"title": .integer(3),
			"logsMatch": .string("yes"),
			"limitedChannelIDs": .array([.integer(1)]),
			"ageLimit": .integer(-1),
			"actionFloodControlInterval": .integer(-5),
			"destination": .integer(9),
			"ageComparator": .integer(99),
			"action": .boolean(true),
		])])

		#expect(Set(result[0].keys) == ["uniqueIdentifier"])
	}

	@Test("Valid fields and fields this build does not know are kept")
	func validAndUnknownFieldsSurvive() throws {
		let fields = rule([
			"title": .string("Greeting"),
			"action": .string("say hi"),
			"destination": .integer(2),
			"ageComparator": .integer(1),
			"ageLimit": .integer(5),
			"limitedChannelIDs": .array([.string("a")]),
			"logsMatch": .boolean(true),
			"futureField": .integer(7),
		])

		#expect(try repaired([fields]) == [fields])
	}

	@Test("An action is bounded so a hand edit cannot amplify into a command flood")
	func actionLength() throws {
		let atLimit = String(repeating: "a", count: 4096)
		let overLimit = String(repeating: "a", count: 4097)

		#expect(try repaired([rule(["action": .string(atLimit)])])[0]["action"] == .string(atLimit))
		#expect(try repaired([rule(["action": .string(overLimit)])])[0]["action"] == nil)
	}

	@Test("Event bits this build does not know are cleared and the known ones kept")
	func eventsAreMasked() throws {
		let known = Int(MessageRuleEvent.plainTextMessage.rawValue | MessageRuleEvent.noticeMessage.rawValue)

		#expect(try repaired([rule(["events": .integer(known | 1 << 20)])])[0]["events"] == .integer(known))
		#expect(try repaired([rule(["events": .integer(-1)])])[0]["events"] == nil)
		#expect(try repaired([rule(["events": .string("all")])])[0]["events"] == nil)
	}

	// MARK: - Identifiers

	@Test("A duplicate, empty or missing identifier is replaced and the first one is kept")
	func identifiersAreRepaired() throws {
		let result = try repaired([
			rule(id: "same"),
			rule(["title": .string("second")], id: "same"),
			rule(id: ""),
			["title": .string("no identifier")],
		])
		let identifiers = try result.map { try #require($0["uniqueIdentifier"]?.string) }

		#expect(identifiers[0] == "same")
		#expect(identifiers.allSatisfy { $0.isEmpty == false })
		#expect(Set(identifiers).count == 4)
		#expect(result[1]["title"] == .string("second"))
	}

	@Test("A value that is not a rule list, or an element that is not a rule, is left alone")
	func nonRulesAreUntouched() throws {
		let repair = try #require(SettingsValueRepair.repairs[SettingsKeys.Rules.messageRules.name])

		#expect(repair(.string("nope")) == .string("nope"))
		#expect(repair(.array([.integer(1)])) == .array([.integer(1)]))
	}

	@Test("A repaired list passes validation")
	func repairedListIsValid() throws {
		let result = try repaired([
			rule(["events": .integer(1 << 30), "ageLimit": .integer(-4)], id: "x"),
			rule(["title": .integer(1)], id: "x"),
		])

		#expect(SettingsValueRepair.messageRules(.array(result.map { .dictionary($0) })))
	}

	// MARK: - Validation

	@Test("Validation wants unique identifiers and fields the repair would not change")
	func validation() {
		func valid(_ rules: [PropertyListValue]) -> Bool {
			SettingsValueRepair.messageRules(.array(rules))
		}

		#expect(valid([.dictionary(rule(id: "a")), .dictionary(rule(["futureField": .integer(1)], id: "b"))]))
		#expect(valid([]))
		#expect(valid([.dictionary(rule(id: "a")), .dictionary(rule(id: "a"))]) == false)
		#expect(valid([.dictionary(rule(id: ""))]) == false)
		#expect(valid([.dictionary(["title": .string("x")])]) == false)
		#expect(valid([.dictionary(rule(["ageLimit": .integer(-1)]))]) == false)
		#expect(valid([.dictionary(rule(["events": .integer(1 << 30)]))]) == false)
		#expect(valid([.integer(1)]) == false)
		#expect(SettingsValueRepair.messageRules(.string("x")) == false)
	}

	@Test("The title and action of each stored rule are read by identifier")
	func messageRuleActions() {
		let value = PropertyListValue.array([
			.dictionary(rule(["title": .string("T"), "action": .string("A")], id: "one")),
			.dictionary(rule(id: "two")),
			.dictionary(["title": .string("orphan")]),
			.integer(1),
		])
		let actions = SettingsValueRepair.messageRuleActions(in: value)

		#expect(actions.keys.sorted() == ["one", "two"])
		#expect(actions["one"]?.title == "T")
		#expect(actions["one"]?.action == "A")
		#expect(actions["two"]?.title == "")
		#expect(actions["two"]?.action == "")
		#expect(SettingsValueRepair.messageRuleActions(in: nil).isEmpty)
	}

	// MARK: - Nickname colours

	private func components(_ red: Double, _ green: Double, _ blue: Double, alpha: Double? = nil) -> PropertyListValue {
		var fields: Fields = ["red": .double(red), "green": .double(green), "blue": .double(blue)]
		fields["alpha"] = alpha.map { .double($0) }

		return .dictionary(fields)
	}

	@Test("Nickname colours must be finite components in 0 to 1")
	func nicknameColors() {
		func valid(_ value: PropertyListValue) -> Bool {
			SettingsValueRepair.nicknameColors(.dictionary(["mara": value]))
		}

		#expect(valid(components(0, 0.5, 1)))
		#expect(valid(components(0, 0.5, 1, alpha: 0.2)))
		#expect(valid(components(1.5, 0, 0)) == false)
		#expect(valid(components(-0.1, 0, 0)) == false)
		#expect(valid(components(.nan, 0, 0)) == false)
		#expect(valid(components(0, 0, 0, alpha: 2)) == false)
		#expect(valid(.dictionary(["red": .double(0), "green": .double(0)])) == false)
		#expect(valid(.data(Data("junk".utf8))) == false)
		#expect(valid(.string("red")) == false)
		#expect(SettingsValueRepair.nicknameColors(.dictionary([:])))
		#expect(SettingsValueRepair.nicknameColors(.array([])) == false)
	}
}
