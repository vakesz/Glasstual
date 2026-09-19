// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation
import Testing

/// Splitting an attributed string into lines, and slicing it by UTF-16 index.
@Suite("Attributed string lines and substrings")
struct AttributedStringSplittingTests {
	private let marker = NSAttributedString.Key("AttributedStringSplittingTestsMarker")

	@Test("Lines split on newlines and keep their attributes")
	func linesSplitPreservingAttributes() throws {
		let source = NSAttributedString(string: "😀 one\ntwo", attributes: [marker: "kept"])
		let lines = source.splitIntoLines

		#expect(lines.map(\.string) == ["😀 one", "two"])
		#expect(try #require(lines[1].attribute(marker, at: 0, effectiveRange: nil) as? String) == "kept")
	}

	@Test("A string with no newline comes back whole")
	func singleLineIsReturnedWhole() {
		#expect(NSAttributedString(string: "one").splitIntoLines.map(\.string) == ["one"])
		#expect(NSAttributedString(string: "").splitIntoLines.isEmpty)
	}

	@Test("A trailing newline does not produce an empty last line")
	func trailingNewlineIsDropped() {
		#expect(NSAttributedString(string: "one\n").splitIntoLines.map(\.string) == ["one"])
	}

	@Test("Substrings from an index use UTF-16 offsets")
	func substringFromIndexUsesUTF16Offsets() {
		let source = NSAttributedString(string: "A😀B")

		#expect(source.attributedSubstring(fromIndex: 1).string == "😀B")
		#expect(source.attributedSubstring(fromIndex: 3).string == "B")
		#expect(source.attributedSubstring(fromIndex: 0).string == "A😀B")
	}
}
