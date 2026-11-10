// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing

/** The duplicate index keeps its newest lines whole and the rest in a reduced
 form. These tests use a limit of four so a dozen lines cross it, and check
 that what a replayed line, a history request and a read marker ask of the
 index is still answered after lines have moved to the older tier. */
@MainActor
@Suite("Scrollback duplicate index bound")
struct ScrollbackDuplicateIndexBoundTests {
	private static let start = Date(timeIntervalSince1970: 1000)
	private let view = "view-\(UUID().uuidString)"

	private func chatLine(_ number: Int, identified: Bool = true) -> ChatLine {
		var line = ChatLine()
		line.messageBody = "body-\(number)"
		line.nickname = "alice"
		line.receivedAt = Self.start.addingTimeInterval(Double(number))
		line.messageIdentifier = identified ? "id-\(number)" : ""
		line.lineType = .privateMessage
		return line
	}

	private func makeIndex(holding lines: [ChatLine]) -> ScrollbackDuplicateIndex {
		let index = ScrollbackDuplicateIndex(recentLimit: 4)
		index.indexChatLines(lines, forView: view)
		return index
	}

	private func hasFallback(_ index: ScrollbackDuplicateIndex, _ number: Int) -> Bool {
		index.containsLine(
			receivedAt: Self.start.addingTimeInterval(Double(number)),
			nickname: "alice",
			messageBody: "body-\(number)",
			forView: view
		)
	}

	@Test("An older line with an identifier is still found by it, and by it alone")
	func olderIdentifiedLinesKeepOnlyTheirIdentifier() {
		let index = makeIndex(holding: (0 ..< 12).map { chatLine($0) })

		for number in 0 ..< 12 {
			#expect(index.containsMessageIdentifier("id-\(number)", forView: view))
		}
		#expect(hasFallback(index, 11))
		#expect(hasFallback(index, 0) == false)
	}

	@Test("An older line without an identifier is still found by its fallback key")
	func olderUnidentifiedLinesKeepTheirFallbackKey() {
		let index = makeIndex(holding: (0 ..< 12).map { chatLine($0, identified: false) })

		for number in 0 ..< 12 {
			#expect(hasFallback(index, number))
		}
	}

	@Test("The newest dates and read marker survive the lines that carry them being demoted")
	func newestDatesDoNotDependOnTheOlderTier() {
		var said = chatLine(0)
		said.serverTimestamp = said.receivedAt
		let narrated = (1 ..< 12).map { number in
			var line = chatLine(number)
			line.lineType = .join
			return line
		}
		let index = makeIndex(holding: [said] + narrated)

		#expect(index.newestLineDate(forView: view) == narrated.last?.receivedAt)
		#expect(index.newestConversationLineDate(forView: view) == said.receivedAt)
		#expect(index.newestReadMarkerTimestamp(forView: view) == said.receivedAt)

		// Pruning the older line that carries them recomputes them rather than keeping a date no stored line has.
		index.forgetLines([said.uniqueIdentifier], inView: view)
		#expect(index.newestConversationLineDate(forView: view) == nil)
		#expect(index.newestReadMarkerTimestamp(forView: view) == nil)
		#expect(index.newestLineDate(forView: view) == narrated.last?.receivedAt)
	}

	@Test("Pruning older lines withdraws them, and counts repeats")
	func pruningOlderLinesReleasesTheirKeys() {
		let first = chatLine(0)
		var repeated = chatLine(1)
		repeated.messageIdentifier = "id-0"
		let index = makeIndex(holding: [first, repeated] + (2 ..< 12).map { chatLine($0) })

		index.forgetLines([first.uniqueIdentifier], inView: view)
		#expect(index.containsMessageIdentifier("id-0", forView: view))

		index.forgetLines([repeated.uniqueIdentifier], inView: view)
		#expect(index.containsMessageIdentifier("id-0", forView: view) == false)
		#expect(index.containsMessageIdentifier("id-11", forView: view))
	}

	@Test("A page of older history goes to the older tier and leaves the newest lines whole")
	func olderPagesDoNotDisplaceNewerLines() {
		let index = makeIndex(holding: (100 ..< 112).map { chatLine($0) })
		let newest = index.newestLineDate(forView: view)

		index.indexChatLines((0 ..< 12).map { chatLine($0) }, forView: view)

		#expect(index.newestLineDate(forView: view) == newest)
		#expect(index.containsMessageIdentifier("id-3", forView: view))
		#expect(hasFallback(index, 111))
		#expect(hasFallback(index, 3) == false)
	}

	@Test("Replacing an older line swaps what it is found by")
	func replacingAnOlderLine() {
		let original = chatLine(0, identified: false)
		let index = makeIndex(holding: [original] + (1 ..< 12).map { chatLine($0, identified: false) })
		var redacted = original
		redacted.messageBody = "[redacted]"

		#expect(index.replaceChatLine(redacted, forView: view))

		#expect(hasFallback(index, 0) == false)
		#expect(index.containsLine(
			receivedAt: original.receivedAt, nickname: "alice", messageBody: "[redacted]", forView: view
		))
	}

	@Test("A removal withdraws lines of both tiers and spares those written after it began")
	func removalCoversBothTiers() {
		let index = makeIndex(holding: (0 ..< 12).map { chatLine($0) })
		let removed = index.beginRemoval(inView: view)
		index.indexChatLine(chatLine(12), forView: view)

		index.removeGenerations(removed, inView: view)
		index.forgetViewIfEmpty(view)

		for number in 0 ..< 12 {
			#expect(index.containsMessageIdentifier("id-\(number)", forView: view) == false)
		}
		#expect(index.containsMessageIdentifier("id-12", forView: view))
		#expect(index.newestLineDate(forView: view) == chatLine(12).receivedAt)
	}

	@Test("A view whose lines are all in the older tier is not forgotten")
	func olderTierAloneKeepsTheView() {
		let lines = (0 ..< 12).map { chatLine($0) }
		let index = makeIndex(holding: lines)
		index.forgetLines(lines.suffix(5).map(\.uniqueIdentifier), inView: view)

		index.forgetViewIfEmpty(view)

		#expect(index.containsMessageIdentifier("id-0", forView: view))
	}

	@Test("Only the canonical spelling of a line identifier is packed")
	func lineKeyPacksOnlyCanonicalIdentifiers() {
		guard case .packed = LineKey(ChatLine.newUniqueIdentifier()) else {
			Issue.record("A minted identifier was not packed")
			return
		}
		#expect(LineKey("ABCD-0123456789AB") == LineKey("ABCD-0123456789AB"))
		#expect(LineKey("ABCD-0123456789AB") != LineKey("ABCD-0123456789AC"))
		#expect(LineKey("ABCD-0123456789AB") != LineKey("abcd-0123456789ab"))
		for other in ["", "ABCD-0123456789ABC", "ABCD0123456789ABC", "ABCD-0123456789A", "ABCG-0123456789AB"] {
			guard case let .text(text) = LineKey(other) else {
				Issue.record("\(other) was packed")
				continue
			}
			#expect(text == other)
		}
	}
}
