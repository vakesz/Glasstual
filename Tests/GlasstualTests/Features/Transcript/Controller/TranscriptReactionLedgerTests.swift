// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
import Foundation
@testable import Glasstual
import Testing

@MainActor
@Suite("Transcript reaction ledger")
struct TranscriptReactionLedgerTests {
	private struct Entry {
		let emoji: String
		let nickname: String
		let message: String

		init(_ emoji: String, _ nickname: String, _ message: String) {
			self.emoji = emoji
			self.nickname = nickname
			self.message = message
		}
	}

	private func ledger(_ entries: [Entry]) -> TranscriptReactionLedger {
		var ledger = TranscriptReactionLedger()
		for entry in entries {
			_ = ledger.record(entry.emoji, from: entry.nickname, forMessage: entry.message)
		}
		return ledger
	}

	@Test("Carrying moves earlier reactors ahead of those already on the new identifier")
	func carryMergesEarlierFirst() {
		var ledger = ledger([.init("👍", "alice", "old"), .init("👍", "bob", "old"), .init("👍", "carol", "new"), .init("👍", "alice", "new")])
		ledger.carry(from: "old", to: "new")
		#expect(ledger.reactions(forMessage: "new")?["👍"] == ["alice", "bob", "carol"])
	}

	@Test("Carrying onto an identifier with no reactions copies them and keeps the old entry")
	func carryCopies() {
		var ledger = ledger([.init("🎉", "alice", "old")])
		ledger.carry(from: "old", to: "new")
		#expect(ledger.reactions(forMessage: "new") == ["🎉": ["alice"]])
		#expect(ledger.reactions(forMessage: "old") == ["🎉": ["alice"]])
	}

	@Test("Carrying keeps reactions the new identifier has that the old one lacks")
	func carryKeepsOtherEmoji() {
		var ledger = ledger([.init("👍", "alice", "old"), .init("❤️", "bob", "new")])
		ledger.carry(from: "old", to: "new")
		#expect(ledger.reactions(forMessage: "new") == ["👍": ["alice"], "❤️": ["bob"]])
	}

	@Test("Carrying keeps the per-reaction cap, favouring the earlier reactors")
	func carryRespectsCap() throws {
		var ledger = TranscriptReactionLedger()
		let cap = TranscriptReactionLedger.maximumReactorsPerReaction
		for index in 0 ..< cap {
			_ = ledger.record("👍", from: "old\(index)", forMessage: "old")
			_ = ledger.record("👍", from: "new\(index)", forMessage: "new")
		}
		ledger.carry(from: "old", to: "new")
		let merged = try #require(ledger.reactions(forMessage: "new")?["👍"])
		#expect(merged.count == cap)
		#expect(merged.first == "old0")
		#expect(merged.last == "old\(cap - 1)")
	}

	@Test("Carrying from an unknown or identical identifier changes nothing")
	func carryNoOps() {
		var ledger = ledger([.init("👍", "alice", "known")])
		let before = ledger.all
		ledger.carry(from: "missing", to: "known")
		ledger.carry(from: "known", to: "known")
		ledger.carry(from: "known", to: "")
		#expect(ledger.all == before)
		#expect(ledger.reactions(forMessage: "missing") == nil)
	}
}
