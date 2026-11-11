// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing

/// What a corpus line should read as.
nonisolated struct XDCCCorpusExpectation: Decodable {
	let kind: String
	let bot: String?
	let pack: Int?
	let filename: String?
	let size: String?
	let gets: Int?
	let packs: Int?
	let open: Int?
	let total: Int?
}

/// One line of `Fixtures/XDCC/announcements.json`.
nonisolated struct XDCCCorpusLine: Decodable, CustomTestStringConvertible {
	let name: String
	let sender: String
	let text: String
	let expect: XDCCCorpusExpectation?

	var testDescription: String {
		name
	}
}

@Suite("XDCC announcement parser")
struct XDCCAnnouncementParserTests {
	nonisolated struct Corpus: Decodable {
		let cases: [XDCCCorpusLine]
	}

	nonisolated static let corpus: [XDCCCorpusLine] = {
		let url = RepositoryPaths.root.appending(path: "Tests/GlasstualTests/Fixtures/XDCC/announcements.json")
		guard let data = try? Data(contentsOf: url),
		      let corpus = try? JSONDecoder().decode(Corpus.self, from: data)
		else { return [] }
		return corpus.cases
	}()

	private static func expected(_ expectation: XDCCCorpusExpectation?) -> XDCCLine? {
		guard let expectation else { return nil }
		switch expectation.kind {
		case "pack":
			return .pack(XDCCPackReference(
				bot: expectation.bot ?? "", pack: expectation.pack ?? 0, filename: expectation.filename,
				sizeText: expectation.size, gets: expectation.gets
			))
		case "header":
			return .listingHeader(packs: expectation.packs, slotsOpen: expectation.open, slotsTotal: expectation.total)
		default:
			return .instruction(bot: expectation.bot ?? "")
		}
	}

	@Test("The corpus is present and covers every kind of line")
	func corpusLoads() {
		let kinds = Set(Self.corpus.compactMap { $0.expect?.kind })
		#expect(Self.corpus.count > 20)
		#expect(kinds == ["pack", "header", "instruction"])
		#expect(Self.corpus.contains { $0.expect == nil })
	}

	@Test("Each corpus line reads as expected", arguments: corpus)
	func corpusLine(_ line: XDCCCorpusLine) {
		let sender = line.sender.isEmpty ? nil : line.sender
		#expect(XDCCAnnouncementParser.parse(line.text.stripIRCEffects, sender: sender) == Self.expected(line.expect))
	}

	@Test("A line past the length cap is not read")
	func lengthCap() {
		let line = "#1 1x [1K] " + String(repeating: "a", count: XDCCAnnouncementParser.maximumLength)
		#expect(XDCCAnnouncementParser.parse(String(line.prefix(XDCCAnnouncementParser.maximumLength)), sender: "Bot") != nil)
		#expect(XDCCAnnouncementParser.parse(line, sender: "Bot") == nil)
	}

	@Test("A listing line from a sender that is not a plausible nickname is not a pack")
	func implausibleSender() {
		#expect(XDCCAnnouncementParser.parse("#1 1x [1K] file.bin", sender: "-bot") == nil)
		#expect(XDCCAnnouncementParser.parse("#1 1x [1K] file.bin", sender: "#bots") == nil)
	}

	@Test("Bot names have to be plausible nicknames", arguments: [
		("Bot", true), ("[Bot]", true), ("Music|Bot", true), ("_bot", true),
		("-bot", false), ("#bot", false), ("1bot", false), ("", false), ("bot!x", false), ("bot name", false),
	])
	func botNames(name: String, plausible: Bool) {
		#expect(XDCCAnnouncementParser.isPlausibleBotName(name) == plausible)
	}
}
