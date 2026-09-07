/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import CocoaExtensions
import Foundation
import Testing

@MainActor
@Suite("Chat Filter export")
struct ChatFilterExportTests {
	@Test("Export writes a property list that the file importer can reopen without losing rule fields")
	func exportedRuleRoundTripsThroughFile() throws {
		var filter = ChatFilter()
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
		filter.limitedClientIDs = ["client-one"]
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
		#expect(dictionary["filterTitle"] == .string("Export fixture"))
		#expect(dictionary["filterAgeLimit"] == .integer(3600))
		#expect(dictionary["filterLimitedToChannelsIDs"]?.stringArray == ["channel-one", "channel-two"])
		let reopened = try ChatFilter(contentsOf: url)
		#expect(reopened.dictionaryValue == filter.dictionaryValue)
	}

	@Test("Default event flags survive the legacy compact export representation")
	func defaultRuleRoundTrips() throws {
		let filter = ChatFilter()
		let data = try filter.propertyListData()
		let raw = try PropertyListSerialization.propertyList(from: data, format: nil)
		let dictionary = try #require([String: PropertyListValue](propertyList: raw))
		let reopened = ChatFilter(dictionary: dictionary)
		#expect(reopened.events == .defaultMessages)
		#expect(reopened.ignoresOperators)
		#expect(reopened.id == filter.id)
		#expect(dictionary["filterAgeComparator"] == nil)
		#expect(reopened.ageComparator == .greaterThan)
		#expect(reopened.dictionaryValue == filter.dictionaryValue)
	}

	@Test("Every explicit age comparator survives export with an active age limit", arguments: [0, 1, 2])
	func ageComparatorRoundTrips(rawValue: Int) throws {
		let filter = ChatFilter(dictionary: [
			"filterAgeComparator": .integer(rawValue),
			"filterAgeLimit": .integer(3600),
		])
		let data = try filter.propertyListData()
		let raw = try PropertyListSerialization.propertyList(from: data, format: nil)
		let dictionary = try #require([String: PropertyListValue](propertyList: raw))
		let reopened = ChatFilter(dictionary: dictionary)
		#expect(reopened.ageComparator.rawValue == UInt(rawValue))
		#expect(reopened.ageLimit == 3600)
	}
}
