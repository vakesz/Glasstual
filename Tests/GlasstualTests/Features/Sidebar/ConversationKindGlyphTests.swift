// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

@testable import Glasstual
import Testing

@MainActor
@Suite("Conversation kind glyphs")
struct ConversationKindGlyphTests {
	@Test("Every kind has a glyph, and people are told apart from channels")
	func glyphs() {
		let kinds: [ConversationRow.Kind] = [.channel, .direct, .directChat, .console]
		let names = kinds.map(\.glyphSymbolName)
		#expect(names.allSatisfy { $0.isEmpty == false })
		#expect(ConversationRow.Kind.channel.glyphSymbolName != ConversationRow.Kind.direct.glyphSymbolName)
		#expect(ConversationRow.Kind.direct.glyphSymbolName == ConversationRow.Kind.console.glyphSymbolName)
	}
}
