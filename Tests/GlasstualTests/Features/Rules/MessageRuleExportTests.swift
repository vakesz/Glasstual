// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation
@testable import Glasstual
import Testing

@MainActor
@Suite("Message rule export")
struct MessageRuleExportTests {
	@Test("Export writes a property list the file importer reopens without losing a field")
	func exportedRuleRoundTripsThroughFile() async throws {
		var filter = MessageRule()
		filter.id = "export-round-trip"
		filter.title = "Export fixture"
		filter.ignoresContent = true
		filter.ignoresOperators = false
		filter.logsMatch = true
		filter.isLimitedToMyself = true
		filter.events = [.noticeMessage, .userJoinedChannel]
		filter.destination = .specificItems
		filter.ageComparator = .lessThan
		filter.ageLimit = 3600
		filter.actionFloodControlInterval = 30
		filter.limitedChannelIDs = ["channel-one", "channel-two"]
		filter.limitedSessionIDs = ["client-one"]
		filter.additionalCommands = ["001", "900"]
		filter.action = "/echo matched"
		filter.forwardDestination = "#archive"
		filter.match = "secret.*"
		filter.notes = "first line\nsecond line"
		filter.senderMatch = "friend!*@*"

		let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).plist")
		defer { try? FileManager.default.removeItem(at: url) }
		try filter.write(to: url)
		let data = try Data(contentsOf: url)
		let raw = try PropertyListSerialization.propertyList(from: data, format: nil)
		let dictionary = try #require([String: PropertyListValue](propertyList: raw))
		#expect(dictionary["title"] == .string("Export fixture"))
		#expect(dictionary["ageLimit"] == .integer(3600))
		#expect(dictionary["limitedChannelIDs"]?.stringArray == ["channel-one", "channel-two"])
		let reopened = try await MessageRule.read(from: url)
		#expect(reopened.dictionaryValue == filter.dictionaryValue)
	}

	@Test("A rule on its defaults exports the fields it changed and reopens unchanged")
	func defaultRuleRoundTrips() throws {
		let filter = MessageRule()
		let data = try filter.propertyListData()
		let raw = try PropertyListSerialization.propertyList(from: data, format: nil)
		let dictionary = try #require([String: PropertyListValue](propertyList: raw))
		let reopened = MessageRule(dictionary: dictionary)
		#expect(reopened.events == .defaultMessages)
		#expect(reopened.ignoresOperators)
		#expect(reopened.id == filter.id)
		#expect(dictionary["ageComparator"] == nil)
		#expect(reopened.ageComparator == .greaterThan)
		#expect(reopened.dictionaryValue == filter.dictionaryValue)
	}

	@Test("Every explicit age comparator survives export with an active age limit", arguments: [0, 1, 2])
	func ageComparatorRoundTrips(rawValue: Int) throws {
		let filter = MessageRule(dictionary: [
			"ageComparator": .integer(rawValue),
			"ageLimit": .integer(3600),
		])
		let data = try filter.propertyListData()
		let raw = try PropertyListSerialization.propertyList(from: data, format: nil)
		let dictionary = try #require([String: PropertyListValue](propertyList: raw))
		let reopened = MessageRule(dictionary: dictionary)
		#expect(reopened.ageComparator.rawValue == UInt(rawValue))
		#expect(reopened.ageLimit == 3600)
	}
}
