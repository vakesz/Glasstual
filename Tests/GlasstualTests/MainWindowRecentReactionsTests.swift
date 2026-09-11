/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

@testable import Glasstual
import Testing

/// The reaction picker is a row of buttons rather than a text field, so what it
/// offers -- and the order it offers it in -- is the whole of the feature.
@Suite("Recent reactions")
struct MainWindowRecentReactionsTests {
	@Test("With nothing remembered the row is the common set")
	func emptyHistoryShowsTheCommonSet() {
		#expect(RecentReactions.row(recent: []) == RecentReactions.common)
	}

	@Test("The row is always the same length")
	func rowLengthIsFixed() {
		#expect(RecentReactions.row(recent: []).count == RecentReactions.rowLength)
		#expect(RecentReactions.row(recent: ["🐢", "🦔", "🦉"]).count == RecentReactions.rowLength)
		#expect(RecentReactions.row(recent: Array(repeating: "🐢", count: 20)).count
			== RecentReactions.rowLength)
	}

	@Test("What was used last leads the row, and the common set fills the rest")
	func recentLeadsTheRow() {
		let row = RecentReactions.row(recent: ["🐢", "🦔"])

		#expect(Array(row.prefix(2)) == ["🐢", "🦔"])
		#expect(Array(row.dropFirst(2)) == Array(RecentReactions.common.prefix(RecentReactions.rowLength - 2)))
	}

	/// A remembered emoji that is also common must appear once, at the front.
	@Test("The row never repeats an emoji")
	func rowHasNoRepeats() throws {
		let common = try #require(RecentReactions.common.first)
		let row = RecentReactions.row(recent: [common])

		#expect(Set(row).count == row.count)
		#expect(row.first == common)
	}

	@Test("Using a reaction moves it to the front")
	func usingAReactionMovesItToTheFront() {
		let stored = RecentReactions.recording("🦉", in: ["🐢", "🦔"])

		#expect(stored == ["🦉", "🐢", "🦔"])
	}

	@Test("Using one that is already remembered does not duplicate it")
	func reusingDoesNotDuplicate() {
		let stored = RecentReactions.recording("🦔", in: ["🐢", "🦔", "🦉"])

		#expect(stored == ["🦔", "🐢", "🦉"])
	}

	@Test("The remembered list stays bounded")
	func rememberedListIsBounded() {
		var stored: [String] = []
		for emoji in ["1️⃣", "2️⃣", "3️⃣", "4️⃣", "5️⃣", "6️⃣", "7️⃣", "8️⃣"] {
			stored = RecentReactions.recording(emoji, in: stored)
		}

		#expect(stored.count == RecentReactions.maximumRememberedCount)
		#expect(stored.first == "8️⃣")
	}

	/** The palette and the pasteboard both hand over whatever the user picked,
	 which is why the same validation guards the bookkeeping: a stray space
	 must not become a remembered reaction, and a longer paste is trimmed to one
	 grapheme. */
	@Test("Only a real emoji is remembered, and only one grapheme of it")
	func onlyRealEmojiAreRemembered() {
		#expect(RecentReactions.recording("   ", in: ["🐢"]) == ["🐢"])
		#expect(RecentReactions.recording("👨‍👩‍👧‍👦 and family", in: []) == ["👨‍👩‍👧‍👦"])
	}
}
