/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

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
}
