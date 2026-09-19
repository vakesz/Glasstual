// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
@testable import Glasstual
import Testing

@MainActor
@Suite("Transcript topic label")
struct TopicLabelTests {
	/// The label's natural width is the whole topic on one line; withholding
	/// it is what keeps the window from growing to the topic's length.
	@Test("The topic label withholds its intrinsic width and keeps its height")
	func topicLabelWithholdsWidth() {
		let label = TopicLabel(wrappingLabelWithString: String(repeating: "topic ", count: 200))
		label.maximumNumberOfLines = 1
		let size = label.intrinsicContentSize
		#expect(size.width == NSView.noIntrinsicMetric)
		#expect(size.height > 0)
	}

	@Test("Topic links dispatch through the text view delegate without changing the topic")
	func topicLinksUseNativeTextInteraction() throws {
		let label = TopicLabel(wrappingLabelWithString: "Read the rules")
		let url = try #require(URL(string: "https://example.test/rules"))
		var opened: [URL] = []
		label.onOpenLink = { opened.append($0) }
		#expect(label.isSelectable)
		#expect(label.isEditable == false)
		#expect(label.textView(label, clickedOnLink: url, at: 0))
		#expect(label.textView(label, clickedOnLink: url.absoluteString, at: 0))
		#expect(opened == [url, url])
		#expect(label.string == "Read the rules")
	}

	@Test("Expanded topic height follows available width and remains bounded")
	func expandedHeightTracksWrappingWidth() {
		let label = TopicLabel(wrappingLabelWithString: String(repeating: "A long channel topic with several words. ", count: 80))
		label.preferredMaxLayoutWidth = 220
		label.maximumNumberOfLines = 1
		let collapsedHeight = label.intrinsicContentSize.height
		label.maximumNumberOfLines = TranscriptTopicBar.expandedTopicLineLimit
		let expandedHeight = label.intrinsicContentSize.height
		#expect(expandedHeight > collapsedHeight)
		#expect(expandedHeight <= collapsedHeight * CGFloat(TranscriptTopicBar.expandedTopicLineLimit))
		#expect(label.textContainer?.maximumNumberOfLines == TranscriptTopicBar.expandedTopicLineLimit)
		#expect(label.textContainer?.containerSize.width == 220)

		label.preferredMaxLayoutWidth = 10000
		#expect(label.intrinsicContentSize.height < expandedHeight)
		#expect(label.intrinsicContentSize.width == NSView.noIntrinsicMetric)
	}
}
