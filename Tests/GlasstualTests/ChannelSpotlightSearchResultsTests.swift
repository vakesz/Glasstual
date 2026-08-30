/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 *********************************************************************** */

@testable import Glasstual
import Testing

/// The rows the spotlight draws used to be an `NSArrayController` filter
/// predicate and a sort descriptor. Now they are a function, so they can be
/// read here rather than inferred from a running table.
@Suite("Channel spotlight search results")
struct ChannelSpotlightSearchResultsTests {
	private struct Candidate: Equatable {
		let name: String
		let clientID: String
		let distance: Double
	}

	private func displayed(
		_ candidates: [Candidate],
		restrictedToClient clientID: String? = nil
	) -> [String] {
		ChannelSpotlightSearchResults.displayed(
			candidates,
			restrictedToClient: clientID,
			distance: \.distance,
			clientID: \.clientID
		)
		.map(\.name)
	}

	@Test("A result that matches too weakly is not shown at all")
	func weakMatchesAreDropped() {
		let candidates = [
			Candidate(name: "#swift", clientID: "a", distance: 0.9),
			Candidate(name: "#nothing", clientID: "a", distance: 0.49),
			Candidate(name: "#borderline", clientID: "a", distance: 0.5),
		]

		#expect(displayed(candidates) == ["#swift", "#borderline"])
	}

	@Test("Results are ordered by how well they match, best first")
	func resultsAreOrderedByDescendingDistance() {
		let candidates = [
			Candidate(name: "#fair", clientID: "a", distance: 0.6),
			Candidate(name: "#best", clientID: "a", distance: 0.95),
			Candidate(name: "#good", clientID: "a", distance: 0.8),
		]

		#expect(displayed(candidates) == ["#best", "#good", "#fair"])
	}

	@Test("Results that match equally well keep the order they arrived in")
	func equalMatchesKeepTheirOrder() {
		let candidates = [
			Candidate(name: "#first", clientID: "a", distance: 0.7),
			Candidate(name: "#second", clientID: "a", distance: 0.7),
			Candidate(name: "#third", clientID: "a", distance: 0.7),
		]

		#expect(displayed(candidates) == ["#first", "#second", "#third"])
	}

	@Test("Restricting to a server keeps only that server's channels")
	func restrictingToAClientFiltersByServer() {
		let candidates = [
			Candidate(name: "#here", clientID: "alpha", distance: 0.9),
			Candidate(name: "#elsewhere", clientID: "beta", distance: 0.95),
			Candidate(name: "#also-here", clientID: "alpha", distance: 0.7),
		]

		#expect(displayed(candidates, restrictedToClient: "alpha") == ["#here", "#also-here"])
	}

	@Test("A server is matched without regard to case, as the predicate did")
	func clientMatchingIsCaseInsensitive() {
		let candidates = [Candidate(name: "#here", clientID: "AlPhA", distance: 0.9)]

		#expect(displayed(candidates, restrictedToClient: "alpha") == ["#here"])
	}

	@Test("No server at all means every server")
	func noRestrictionShowsEveryServer() {
		let candidates = [
			Candidate(name: "#alpha", clientID: "alpha", distance: 0.9),
			Candidate(name: "#beta", clientID: "beta", distance: 0.8),
		]

		#expect(displayed(candidates) == ["#alpha", "#beta"])
	}

	@Test("Restricting to no server at all — what an unselected client meant — shows nothing")
	func restrictingToAnEmptyClientShowsNothing() {
		let candidates = [
			Candidate(name: "#alpha", clientID: "alpha", distance: 0.9),
			Candidate(name: "#beta", clientID: "beta", distance: 0.8),
		]

		#expect(displayed(candidates, restrictedToClient: "").isEmpty)
	}
}
