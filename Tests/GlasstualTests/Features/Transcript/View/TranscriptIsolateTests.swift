// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
import Foundation
@testable import Glasstual
import Testing

@MainActor
@Suite("Transcript directional isolate")
struct TranscriptIsolateTests {
	@Test("Text is wrapped in isolate characters marked as padding, without clickable attributes")
	func wraps() {
		let result = NSMutableAttributedString(string: "x")
		let body = NSAttributedString(string: "hello")
		let link = URL(filePath: "/tmp/example")
		let attributes: [NSAttributedString.Key: Any] = [
			.transcriptAction: "do",
			.link: link,
			.foregroundColor: NSColor.red,
		]
		TranscriptIsolate.appendIsolated(body, to: result, isolateAttributes: attributes)
		#expect(result.string == "x\(TranscriptIsolate.isolateStart)hello\(TranscriptIsolate.isolateEnd)")
		for index in [1, 7] {
			let applied = result.attributes(at: index, effectiveRange: nil)
			#expect(applied[.transcriptPadding] as? Bool == true)
			#expect(applied[.transcriptAction] == nil)
			#expect(applied[.link] == nil)
			#expect(applied[.foregroundColor] != nil)
		}
	}

	@Test("Empty text appends nothing")
	func empty() {
		let result = NSMutableAttributedString(string: "x")
		TranscriptIsolate.appendIsolated(NSAttributedString(), to: result, isolateAttributes: [:])
		#expect(result.string == "x")
	}
}
