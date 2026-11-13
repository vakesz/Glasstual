// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
@testable import Glasstual
import Testing

@MainActor
@Suite("Transcript reverse colours")
struct TranscriptReverseColorsTests {
	@Test("A run that is not reversed keeps its colours")
	func plainRunIsUntouched() {
		let colors = TranscriptReverseColors.resolve(
			foreground: .red, background: .blue, isReversed: false, fallbackBackground: .green
		)
		#expect(colors == TranscriptReverseColors(foreground: .red, background: .blue))
		let bare = TranscriptReverseColors.resolve(
			foreground: .red, background: nil, isReversed: false, fallbackBackground: .green
		)
		#expect(bare == TranscriptReverseColors(foreground: .red, background: nil))
	}

	@Test("A reversed run with both colours swaps them")
	func reversedRunSwaps() {
		let colors = TranscriptReverseColors.resolve(
			foreground: .red, background: .blue, isReversed: true, fallbackBackground: .green
		)
		#expect(colors == TranscriptReverseColors(foreground: .blue, background: .red))
	}

	@Test("A reversed run with no background takes the ground it sits on as its text colour")
	func reversedRunUsesTheGround() {
		let colors = TranscriptReverseColors.resolve(
			foreground: .red, background: nil, isReversed: true, fallbackBackground: .green
		)
		#expect(colors == TranscriptReverseColors(foreground: .green, background: .red))
	}

	@Test("The renderer marks a reversed run and not an italic one")
	func rendererCarriesReverse() {
		let body = TranscriptRenderer.renderNativeBody(
			"a\u{16}reversed\u{16} b", withAttributes: TranscriptRenderOptions(), members: []
		)
		#expect(body.runs == [
			TranscriptTextRun(text: "a"),
			TranscriptTextRun(text: "reversed", traits: .reverse),
			TranscriptTextRun(text: " b"),
		])
	}

	@Test("Formatted text outside the transcript swaps its colours and adds no formatter key")
	func formattedTextSwaps() {
		let font = NSFont.systemFont(ofSize: 12)
		let rendered = TranscriptFormattedText.render(
			"\u{16}swap",
			with: TranscriptFormattingAttributes(preferredFont: font, preferredFontColor: .labelColor)
		)
		#expect(rendered.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor == .textBackgroundColor)
		#expect(rendered.attribute(.backgroundColor, at: 0, effectiveRange: nil) as? NSColor == .labelColor)
		#expect(rendered.attribute(
			NSAttributedString.Key(TextFormatterAttributeName.foregroundColorAttributeName.rawValue),
			at: 0, effectiveRange: nil
		) == nil)
	}
}
