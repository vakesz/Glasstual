// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
import CocoaExtensions
import Testing

@MainActor
@Suite("Plain text clipboard replacement")
struct PasteboardStringContentTests {
	@Test("Copying a URL or identifier removes older rich text", arguments: [
		"https://example.test/rules?channel=swift",
		"E47BF847-F817-4C1E-8550-9044D87046CB",
	])
	func replacingRichText(_ value: String) {
		let pasteboard = NSPasteboard.withUniqueName()
		defer { pasteboard.releaseGlobally() }
		pasteboard.declareTypes([.string, .rtf, .html], owner: nil)
		pasteboard.setString("old message", forType: .string)
		pasteboard.setData(Data("{\\rtf1 old message}".utf8), forType: .rtf)
		pasteboard.setString("<strong>old message</strong>", forType: .html)

		pasteboard.stringContent = value

		#expect(pasteboard.stringContent == value)
		#expect(pasteboard.data(forType: .rtf) == nil)
		#expect(pasteboard.string(forType: .html) == nil)
		#expect(pasteboard.types?.contains(.string) == true)
	}
}
