/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import CocoaExtensions
import Foundation
@testable import Glasstual
import Testing

/// The condition keeps the key spellings the Objective-C original wrote,
/// `matchChannelID` among them, so stored highlight lists still load.
@Suite("Highlight condition property-list round trip")
struct IRCHighlightMatchConditionCodableTests {
	@Test("A dictionary written by the previous release re-encodes unchanged")
	func roundTripsAStoredDictionary() throws {
		// Captured from the class-based `HighlightMatchCondition.dictionaryValue`.
		let fixture: [String: PropertyListValue] = [
			"matchChannelID": "8B2F4C1A-0000-4000-8000-000000000002",
			"matchKeyword": "release",
			"uniqueIdentifier": "8B2F4C1A-0000-4000-8000-000000000003",
			"matchIsExcluded": true,
		]

		let condition = try #require(PropertyListModel.decode(HighlightMatchCondition.self, from: fixture))

		#expect(PropertyListModel.encode(condition) == fixture)
	}

	@Test("An absent channel stays absent rather than becoming an empty string")
	func absentChannelStaysNil() throws {
		let condition = try #require(PropertyListModel.decode(HighlightMatchCondition.self, from: [
			"matchKeyword": "release",
		]))

		#expect(condition.matchChannelId == nil)
		#expect(PropertyListModel.encode(condition)["matchChannelID"] == nil)
	}

	@Test("A condition with no keyword loads but reports itself malformed")
	func aKeywordlessConditionIsFlagged() throws {
		let condition = try #require(PropertyListModel.decode(HighlightMatchCondition.self, from: [
			"matchIsExcluded": true,
		]))

		#expect(condition.isWellFormed == false)
		#expect(condition.uniqueIdentifier.isEmpty == false)
	}
}
