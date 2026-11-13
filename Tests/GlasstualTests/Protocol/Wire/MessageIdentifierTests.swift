// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing

@MainActor
@Suite("Opaque IRC message identifiers")
struct MessageIdentifierTests {
	private let composed = "é"
	private let decomposed = "e\u{301}"

	@Test("Lookup keys distinguish Unicode-equivalent spellings without changing their bytes")
	func opaqueKeys() {
		#expect(composed == decomposed, "This deliberately exercises Swift's canonical String equality")
		#expect(MessageIdentifierKey(composed) != MessageIdentifierKey(decomposed))
		#expect(Set([MessageIdentifierKey(composed), MessageIdentifierKey(decomposed)]).count == 2)
		#expect(!MessageIdentifierKey.equal(composed, decomposed))
		#expect(MessageIdentifierKey.equal(nil, nil))
		#expect(Array(MessageIdentifierKey(decomposed).rawValue.utf8) == Array(decomposed.utf8))
	}

	@Test("Deduplication and retirement do not merge byte-distinct message IDs")
	func duplicateIndex() {
		let index = ScrollbackDuplicateIndex()
		let first = line(identifier: composed)
		let second = line(identifier: decomposed)
		index.indexChatLine(first, forView: "view")
		#expect(index.containsMessageIdentifier(composed, forView: "view"))
		#expect(!index.containsMessageIdentifier(decomposed, forView: "view"))
		index.indexChatLine(second, forView: "view")
		index.forgetLines([first.uniqueIdentifier], inView: "view")
		#expect(!index.containsMessageIdentifier(composed, forView: "view"))
		#expect(index.containsMessageIdentifier(decomposed, forView: "view"))
	}

	@Test("Reply ranges and reactions target only the exact message")
	func documentAndReactions() {
		var ledger = TranscriptReactionLedger()
		_ = ledger.record("👍", from: "alice", forMessage: composed)
		_ = ledger.record("🎉", from: "bob", forMessage: decomposed)
		#expect(ledger.all.count == 2)
		let context = TranscriptRenderContext(sessionReactions: ledger.all)
		let rows = [composed, decomposed].map { identifier in
			TranscriptController.renderJob(TranscriptRenderRequest(
				line: ChatLineSnapshot(line(identifier: identifier), in: context), context: context
			)).transcriptLine
		}
		var document = TranscriptDocument()
		document.insert(rows, at: 0, starts: [0, 1], totalLength: 2)
		#expect(document.range(ofMessage: composed) == NSRange(location: 0, length: 1))
		#expect(document.range(ofMessage: decomposed) == NSRange(location: 1, length: 1))
		#expect(document[0].reactions == ["👍": ["alice"]])
		#expect(document[1].reactions == ["🎉": ["bob"]])
		#expect(document.mergeReactions(["✅": ["carol"]], messageIdentifier: composed) == [0])
		#expect(document[1].reactions["✅"] == nil)
		ledger.forget([composed], stillHeld: { _ in false })
		#expect(ledger.reactions(forMessage: composed) == nil)
		#expect(ledger.reactions(forMessage: decomposed) == ["🎉": ["bob"]])
	}

	@Test("Buffered projections and archived wire identifiers preserve the same distinction")
	func bufferedAndArchived() throws {
		var projection = TranscriptProjectionState(capacity: 1)
		let context = TranscriptRenderContext()
		for identifier in [composed, decomposed] {
			let line = line(identifier: identifier)
			_ = projection.record(TranscriptController.renderJob(TranscriptRenderRequest(
				line: ChatLineSnapshot(line, in: context), context: context
			)))
			let restored = try #require(ChatLine(entry: line.scrollbackEntry(forView: "view")))
			#expect(try Array(#require(restored.messageIdentifier).utf8) == Array(identifier.utf8))
		}
		#expect(!projection.containsMessage(withIdentifier: composed))
		#expect(projection.containsMessage(withIdentifier: decomposed))
	}

	private func line(identifier: String) -> ChatLine {
		var line = ChatLine()
		line.lineType = .privateMessage
		line.messageBody = "x"
		line.messageIdentifier = identifier
		return line
	}
}
