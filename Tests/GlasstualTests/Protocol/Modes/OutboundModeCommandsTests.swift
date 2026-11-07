// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing

/// How a mode change is cut into commands a server will take.
struct OutboundModeCommandsTests {
	private static let takesParameter: (Character, Bool) -> Bool = { symbol, isSet in
		switch symbol {
		case "o", "v", "b", "k": true
		case "l": isSet
		default: false
		}
	}

	private func groups(_ tokens: [String]) -> [ModeChangeGroup] {
		OutboundModeCommands.groups(inTokens: tokens, modeTakesParameter: Self.takesParameter)
	}

	// MARK: - Reading tokens

	@Test("Parameters belong to the letters that are owed them")
	func parametersFollowTheirLetters() {
		#expect(groups(["+ooo", "a", "b", "c"]) == [ModeChangeGroup(symbols: "+ooo", parameters: ["a", "b", "c"])])
	}

	@Test("A key that looks like a mode string is still the key")
	func keyThatLooksLikeAModeString() {
		#expect(groups(["+k", "+secret"]) == [ModeChangeGroup(symbols: "+k", parameters: ["+secret"])])
	}

	@Test("Two mode strings are two independent groups")
	func twoModeStringsSplit() {
		#expect(
			groups(["+s", "+cfk", "key"])
				== [ModeChangeGroup(symbols: "+s"), ModeChangeGroup(symbols: "+cfk", parameters: ["key"])]
		)
	}

	@Test("Whether a letter is owed a parameter follows its sign")
	func signDecidesWhetherAParameterIsOwed() {
		#expect(groups(["-l", "+n"]) == [ModeChangeGroup(symbols: "-l"), ModeChangeGroup(symbols: "+n")])
		#expect(groups(["+l", "5", "+n"]) == [
			ModeChangeGroup(symbols: "+l", parameters: ["5"]),
			ModeChangeGroup(symbols: "+n"),
		])
	}

	@Test("Empty tokens are skipped and a leading bare word opens a group")
	func emptyAndLeadingTokens() {
		#expect(groups(["", "+o", "", "a"]) == [ModeChangeGroup(symbols: "+o", parameters: ["a"])])
		#expect(groups(["nt"]) == [ModeChangeGroup(symbols: "nt")])
		#expect(groups([]).isEmpty)
	}

	@Test("An extra parameter attaches to the group it follows")
	func surplusParameterAttaches() {
		#expect(groups(["+nt", "extra"]) == [ModeChangeGroup(symbols: "+nt", parameters: ["extra"])])
	}

	// MARK: - Splitting

	private func split(
		_ symbols: String,
		_ parameters: [String],
		maximumModes: UInt = 0,
		budget: Int = .max
	) -> [ModeChangeGroup] {
		OutboundModeCommands.groups(
			for: ModeChangeGroup(symbols: symbols, parameters: parameters),
			maximumModes: maximumModes,
			budget: budget
		)
	}

	@Test("MODES caps the changes in one command")
	func modesCapsTheCount() {
		let result = split("+ooooooo", ["a", "b", "c", "d", "e", "f", "g"], maximumModes: 3)

		#expect(result.map(\.symbols) == ["+ooo", "+ooo", "+o"])
		#expect(result.flatMap(\.parameters) == ["a", "b", "c", "d", "e", "f", "g"])
	}

	@Test("A server that names no limit gets the whole change")
	func zeroModesMeansNoLimit() {
		#expect(split("+ooo", ["a", "b", "c"]).count == 1)
	}

	@Test("The byte budget splits earlier than MODES would")
	func budgetSplits() {
		/* "+o a" costs 4 and each further "o b" costs 3. */
		#expect(split("+ooo", ["a", "b", "c"], maximumModes: 10, budget: 7).map(\.parameters) == [["a", "b"], ["c"]])
		#expect(split("+ooo", ["a", "b", "c"], maximumModes: 10, budget: 6).map(\.parameters) == [["a"], ["b"], ["c"]])
	}

	@Test("A sign is charged only where it turns")
	func signCostsOnlyOnATurn() {
		/* Same budget as above: a flipped sign repeats the sign byte, so it no longer fits. */
		#expect(split("+o-o", ["a", "b"], budget: 7).count == 2)
		#expect(split("+oo", ["a", "b"], budget: 7).count == 1)
	}

	@Test("Sign turns are rebuilt without repeating a sign")
	func signsAreRebuilt() {
		let result = split("+o-o+o", ["a", "b", "c"])

		#expect(result == [ModeChangeGroup(symbols: "+o-o+o", parameters: ["a", "b", "c"])])
		#expect(split("+o-o+o", ["a", "b", "c"], maximumModes: 2).map(\.symbols) == ["+o-o", "+o"])
	}

	@Test("Parameters are costed in bytes")
	func parametersCostBytes() {
		/* "é" is two bytes: "+o é" costs 5 and "o é" costs 4, together 9. */
		#expect(split("+oo", ["é", "é"], budget: 9).count == 1)
		#expect(split("+oo", ["é", "é"], budget: 8).count == 2)
	}

	@Test("A change that cannot be paired goes out whole", arguments: [
		("+nt", [String]()),
		("+k", ["key"]),
		("+ob", ["a"]),
		("-k+l", ["only-one"]),
	])
	func unpairableChangeIsWhole(_ symbols: String, _ parameters: [String]) {
		#expect(split(symbols, parameters, maximumModes: 1, budget: 1) == [ModeChangeGroup(symbols: symbols, parameters: parameters)])
	}
}
