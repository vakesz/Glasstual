// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
@testable import Glasstual
import Testing

/** How much text the bottom-alignment check lays out.

 A short transcript sits beside the input bar; a long one starts at the top.
 Telling the two apart needs only enough of the text to fill the viewport, and
 the check runs after every batch of lines, so laying out more than that makes
 every incoming line cost a pass over the whole transcript. */
@MainActor
@Suite("Transcript text view bottom alignment")
struct TranscriptTextViewBottomAlignmentTests {
	@Test("A long transcript is told apart from a short one without laying out its end")
	func longTranscriptLaysOutOnlyTheViewport() throws {
		let (_, textView) = Self.makeTextView()
		let lines = (0 ..< 5000).map { "line \($0)" }.joined(separator: "\n")
		textView.textStorage?.setAttributedString(NSAttributedString(string: lines))
		let layoutManager = try #require(textView.textLayoutManager)

		textView.updateBottomAlignment()

		#expect(textView.textContainerOrigin.y == textView.textContainerInset.height)
		let end = try #require(layoutManager.location(layoutManager.documentRange.endLocation, offsetBy: -1))
		let last = try #require(layoutManager.textLayoutFragment(for: end))
		#expect(last.state != .layoutAvailable)
	}

	@Test("A short transcript is aligned to the bottom of the viewport")
	func shortTranscriptIsBottomAligned() {
		let (_, textView) = Self.makeTextView()
		textView.textStorage?.setAttributedString(NSAttributedString(string: "one\ntwo"))

		textView.updateBottomAlignment()

		#expect(textView.textContainerOrigin.y > 100)
	}

	private static func makeTextView() -> (NSScrollView, TranscriptTextView) {
		let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
		let textView = TranscriptTextView(usingTextLayoutManager: true)
		textView.frame = NSRect(x: 0, y: 0, width: 400, height: 300)
		textView.isVerticallyResizable = true
		textView.textContainer?.widthTracksTextView = true
		scrollView.documentView = textView
		return (scrollView, textView)
	}
}
