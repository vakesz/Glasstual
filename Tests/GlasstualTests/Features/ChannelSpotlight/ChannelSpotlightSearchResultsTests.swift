// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing

/// The rows the spotlight draws used to be an `NSArrayController` filter
/// predicate and a sort descriptor. Now they are a function, so they can be
/// read here rather than inferred from a running table.
@Suite("Channel spotlight search results")
struct ChannelSpotlightSearchResultsTests {
	private func candidate(name: String, sessionID: String, distance: Double) -> ChannelSpotlightSearchResult {
		ChannelSpotlightSearchResult(
			id: "\(sessionID)/\(name)",
			sessionID: sessionID,
			conversationName: name,
			networkName: "Example",
			distance: distance
		)
	}

	private func displayed(
		_ candidates: [ChannelSpotlightSearchResult],
		restrictedToSession sessionID: String? = nil
	) -> [String] {
		ChannelSpotlightSearchResults.displayed(candidates, restrictedToSession: sessionID)
			.map(\.conversationName)
	}

	@Test("A result that matches too weakly is not shown at all")
	func weakMatchesAreDropped() {
		let candidates = [
			candidate(name: "#swift", sessionID: "a", distance: 0.9),
			candidate(name: "#nothing", sessionID: "a", distance: 0.49),
			candidate(name: "#borderline", sessionID: "a", distance: 0.5),
		]

		#expect(displayed(candidates) == ["#swift", "#borderline"])
	}

	@Test("Results are ordered by how well they match, best first")
	func resultsAreOrderedByDescendingDistance() {
		let candidates = [
			candidate(name: "#fair", sessionID: "a", distance: 0.6),
			candidate(name: "#best", sessionID: "a", distance: 0.95),
			candidate(name: "#good", sessionID: "a", distance: 0.8),
		]

		#expect(displayed(candidates) == ["#best", "#good", "#fair"])
	}

	@Test("Results that match equally well keep the order they arrived in")
	func equalMatchesKeepTheirOrder() {
		let candidates = [
			candidate(name: "#first", sessionID: "a", distance: 0.7),
			candidate(name: "#second", sessionID: "a", distance: 0.7),
			candidate(name: "#third", sessionID: "a", distance: 0.7),
		]

		#expect(displayed(candidates) == ["#first", "#second", "#third"])
	}

	@Test("Restricting to a server keeps only that server's channels")
	func restrictingToASessionFiltersByServer() {
		let candidates = [
			candidate(name: "#here", sessionID: "alpha", distance: 0.9),
			candidate(name: "#elsewhere", sessionID: "beta", distance: 0.95),
			candidate(name: "#also-here", sessionID: "alpha", distance: 0.7),
		]

		#expect(displayed(candidates, restrictedToSession: "alpha") == ["#here", "#also-here"])
	}

	@Test("A server is matched without regard to case, as the predicate did")
	func sessionMatchingIsCaseInsensitive() {
		let candidates = [candidate(name: "#here", sessionID: "AlPhA", distance: 0.9)]

		#expect(displayed(candidates, restrictedToSession: "alpha") == ["#here"])
	}

	@Test("No server at all means every server")
	func noRestrictionShowsEveryServer() {
		let candidates = [
			candidate(name: "#alpha", sessionID: "alpha", distance: 0.9),
			candidate(name: "#beta", sessionID: "beta", distance: 0.8),
		]

		#expect(displayed(candidates) == ["#alpha", "#beta"])
	}

	@Test("Restricting to no server at all — what an unselected session meant — shows nothing")
	func restrictingToAnEmptySessionShowsNothing() {
		let candidates = [
			candidate(name: "#alpha", sessionID: "alpha", distance: 0.9),
			candidate(name: "#beta", sessionID: "beta", distance: 0.8),
		]

		#expect(displayed(candidates, restrictedToSession: "").isEmpty)
	}
}

/// The two lines a spotlight row draws, which are the result's own answers so
/// that they can be read here rather than out of a rendered row.
@Suite("Channel spotlight result presentation")
struct ChannelSpotlightResultPresentationTests {
	private func result(
		channel: String = "#swift",
		network: String = "Libera.Chat",
		highlights: Int = 0,
		unread: Int = 0
	) -> ChannelSpotlightSearchResult {
		ChannelSpotlightSearchResult(
			id: channel,
			sessionID: "session",
			conversationName: channel,
			networkName: network,
			highlightCount: highlights,
			unreadCount: unread
		)
	}

	@Test("A channel is titled by the network it is on, and by itself when it has none")
	func titleNamesTheNetworkOnlyWhenThereIsOne() {
		#expect(result().title == "#swift on Libera.Chat")
		/* The suffix used to be glued on unconditionally, so a channel with no
		 server read as "#swift on " with nothing after it. */
		#expect(result(network: "").title == "#swift")
	}

	@Test("A channel with nothing waiting says nothing")
	func quietChannelsHaveNoActivityLine() {
		#expect(result().activity == nil)
	}

	@Test("Only the counts that are not zero are named")
	func activityNamesWhatThereIsToCount() throws {
		let unreadOnly = try #require(result(unread: 4).activity)
		#expect(unreadOnly.contains("4"))
		#expect(unreadOnly.localizedCaseInsensitiveContains("highlight") == false)

		let highlightsOnly = try #require(result(highlights: 2).activity)
		#expect(highlightsOnly.localizedCaseInsensitiveContains("highlight"))
		#expect(highlightsOnly.localizedCaseInsensitiveContains("unread") == false)

		let both = try #require(result(highlights: 2, unread: 4).activity)
		#expect(both.localizedCaseInsensitiveContains("highlight"))
		#expect(both.localizedCaseInsensitiveContains("unread"))
	}

	@Test("Scoring a result against nothing leaves it unranked")
	func scoringAgainstAnEmptySearchIsZero() {
		#expect(result().scored(against: "").distance == 0)
		#expect(result().scored(against: "swift").distance > 0)
	}
}
