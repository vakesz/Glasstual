// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation
@testable import Glasstual
import Testing

/// Every field of a stored condition is named after the property it sets, and an
/// absent channel stays absent.
@Suite("Highlight condition property-list round trip")
struct HighlightMatchConditionCodableTests {
	@Test("A stored condition re-encodes unchanged")
	func roundTripsAStoredDictionary() throws {
		let fixture: [String: PropertyListValue] = [
			"matchChannelId": "8B2F4C1A-0000-4000-8000-000000000002",
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
		#expect(PropertyListModel.encode(condition)["matchChannelId"] == nil)
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
