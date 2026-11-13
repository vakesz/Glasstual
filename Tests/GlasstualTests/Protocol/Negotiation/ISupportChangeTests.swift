// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing

@Suite("ISUPPORT token reading")
struct ISupportChangeTests {
	@Test("A count a token does not take falls through to its text reading")
	func countFallsThroughToText() {
		#expect(ISupportChange.reading(.network, value: "42") == [.networkName("42")])
	}

	@Test("A count token whose value is not a positive count changes nothing", arguments: ["abc", "0", "50abc", ""])
	func malformedCountIsIgnored(_ value: String) {
		#expect(ISupportChange.reading(.nicklen, value: value).isEmpty)
	}

	@Test("LINELEN is clamped to the longest line a server may send")
	func lineLengthIsClamped() {
		let limit = UInt(ProtocolLimits.maximumServerLineLength)
		#expect(ISupportChange.reading(.linelen, value: "\(limit + 1)") == [.count(.lineLength, limit)])
	}

	@Test("MONITOR reads its count before the capability it announces")
	func monitorReadsValueThenAnnouncement() {
		#expect(ISupportChange.reading(.monitor, value: "100") == [
			.count(.monitorEntries, 100), .enablesCapability(.monitorCommand),
		])
		#expect(ISupportChange.reading(.monitor, value: nil) == [.enablesCapability(.monitorCommand)])
	}

	@Test("An empty PREFIX clears the prefixes; an unreadable one changes nothing")
	func prefixReading() {
		#expect(ISupportChange.reading(.prefix, value: "") == [.userModePrefixes(modeSymbols: [], characters: [])])
		#expect(ISupportChange.reading(.prefix, value: "(qaohv)~&@%+") == [
			.userModePrefixes(modeSymbols: ["q", "a", "o", "h", "v"], characters: ["~", "&", "@", "%", "+"]),
		])
	}

	@Test("A mode-letter token falls back to the usual letter unless it names a valid one")
	func modeLetterFallback() {
		#expect(ISupportChange.reading(.excepts, value: nil) == [.modeSymbol(.banException, "e")])
		#expect(ISupportChange.reading(.excepts, value: "x") == [.modeSymbol(.banException, "x")])
		#expect(ISupportChange.reading(.excepts, value: "xy") == [.modeSymbol(.banException, "e")])
		#expect(ISupportChange.reading(.bot, value: nil).isEmpty)
	}

	@Test("SILENCE is supported with or without a readable list size")
	func silenceReading() {
		#expect(ISupportChange.reading(.silence, value: "15") == [.silenceSupported(maximumEntries: 15)])
		#expect(ISupportChange.reading(.silence, value: "many") == [.silenceSupported(maximumEntries: nil)])
	}

	@Test(
		"CASEMAPPING names map to the casefold they mean, and unknown names to rfc1459",
		arguments: [
			("ascii", ISupportCaseMapping.ascii),
			("STRICT-RFC1459", .strictRFC1459),
			("rfc8265", .rfc7613),
			("rfc7613", .rfc7613),
			("unknown", .rfc1459),
		]
	)
	func caseMappingNames(_ name: String, _ expected: ISupportCaseMapping) {
		#expect(ISupportChange.reading(.casemapping, value: name) == [.caseMapping(expected)])
	}

	@Test("NAMESX asks for its legacy capability by the pre-CAP line")
	func legacyCapability() {
		#expect(ISupportChange.reading(.namesx, value: nil) == [.legacyCapability(
			ISupportEffects.LegacyCapability(capability: .multiPrefix, command: "PROTOCTL NAMESX")
		)])
	}
}
