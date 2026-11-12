// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
@testable import Glasstual
import Testing

/// VoiceOver's rotors over the transcript move between messages, mentions,
/// links and days; each search lands on the next or previous one from where
/// the reader is.
@Suite("Transcript rotor search")
struct TranscriptRotorSearchTests {
	private let items = [
		TranscriptRotorItem(range: NSRange(location: 0, length: 10), label: "alice: hello"),
		TranscriptRotorItem(range: NSRange(location: 10, length: 10), label: "bob: release notes"),
		TranscriptRotorItem(range: NSRange(location: 20, length: 10), label: "carol: hello again"),
	]

	@Test("With no current item a search starts at the first or the last")
	func startsAtTheEnds() {
		#expect(TranscriptRotorSearch.index(in: items, from: nil, forward: true) == 0)
		#expect(TranscriptRotorSearch.index(in: items, from: nil, forward: false) == 2)
		let notFound = NSRange(location: NSNotFound, length: 0)
		#expect(TranscriptRotorSearch.index(in: items, from: notFound, forward: true) == 0)
	}

	@Test("Next and previous move one item from the current one, and stop at the ends")
	func movesOneItem() {
		#expect(TranscriptRotorSearch.index(in: items, from: items[0].range, forward: true) == 1)
		#expect(TranscriptRotorSearch.index(in: items, from: items[1].range, forward: false) == 0)
		#expect(TranscriptRotorSearch.index(in: items, from: items[2].range, forward: true) == nil)
		#expect(TranscriptRotorSearch.index(in: items, from: items[0].range, forward: false) == nil)
	}

	@Test("A caret inside an item moves to the one after it")
	func caretInsideAnItem() {
		let caret = NSRange(location: 14, length: 0)
		#expect(TranscriptRotorSearch.index(in: items, from: caret, forward: true) == 2)
		#expect(TranscriptRotorSearch.index(in: items, from: caret, forward: false) == 1)
	}

	@Test("A filter keeps only the items whose label contains it")
	func filters() {
		#expect(TranscriptRotorSearch.index(in: items, from: nil, forward: true, filter: "HELLO") == 0)
		#expect(TranscriptRotorSearch.index(in: items, from: items[0].range, forward: true, filter: "hello") == 2)
		#expect(TranscriptRotorSearch.index(in: items, from: nil, forward: true, filter: "nothing") == nil)
	}
}

/// What the transcript keeps clear above its first line, and how big the
/// picture beside a sender is drawn.
@Suite("Transcript layout metrics")
struct TranscriptLayoutMetricsTests {
	@Test("The top inset is the safe area plus a shown topic bar")
	func topInset() {
		#expect(TranscriptMetrics.topContentInset(safeAreaTop: 52, topicBarHeight: nil) == 52)
		#expect(TranscriptMetrics.topContentInset(safeAreaTop: 52, topicBarHeight: 33) == 85)
		#expect(TranscriptMetrics.topContentInset(safeAreaTop: 0, topicBarHeight: 33) == 33)
	}

	@Test("The toolbar strip draws its hairline only under a toolbar with no topic bar beneath it")
	func toolbarSeparator() {
		#expect(TranscriptMetrics.showsToolbarSeparator(safeAreaTop: 52, topicBarIsShown: false))
		#expect(TranscriptMetrics.showsToolbarSeparator(safeAreaTop: 52, topicBarIsShown: true) == false)
		#expect(TranscriptMetrics.showsToolbarSeparator(safeAreaTop: 0, topicBarIsShown: false) == false)
	}

	@Test("A sender's picture grows with the name's font and sits on its baseline", arguments: [11.0, 13.0, 20.0])
	@MainActor
	func avatarFollowsTheFont(pointSize: Double) {
		let font = NSFont.systemFont(ofSize: pointSize)
		let bounds = TranscriptView.senderAvatarBounds(for: font)
		#expect(bounds.width == bounds.height)
		#expect(bounds.height >= font.ascender - font.descender)
		#expect(bounds.minY <= 0)
		#expect(bounds.minY > -pointSize)
	}
}
