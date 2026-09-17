// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

@testable import Glasstual
import Testing

@MainActor
@Suite("Main-window typing redirection")
struct MainWindowTypingRedirectPolicyTests {
	@Test("Printable text typed in a sidebar is redirected to the message input")
	func printableTextIsRedirected() {
		#expect(
			TypingRedirect.text(
				for: "Å",
				commandIsPressed: false,
				controlIsPressed: false
			) == "Å"
		)
	}

	/** AppKit maps the arrow, function, page and Home/End keys into the Unicode
	 private-use area rather than to control characters, so they passed the
	 control-character test: pressing an arrow key in a sidebar inserted an
	 undrawable character into the message field instead of moving the
	 selection. */
	@Test(
		"Function keys mapped into the private-use area stay with the sidebar",
		arguments: [0xF700, 0xF701, 0xF702, 0xF703, 0xF72B, 0xF8FF]
	)
	func functionKeysAreNotRedirected(scalarValue: Int) throws {
		let scalar = try #require(Unicode.Scalar(UInt32(scalarValue)))

		#expect(
			TypingRedirect.text(
				for: String(Character(scalar)),
				commandIsPressed: false,
				controlIsPressed: false
			) == nil
		)
	}

	@Test("Commands and navigation control characters stay with the sidebar")
	func commandsAndControlsAreNotRedirected() {
		#expect(
			TypingRedirect.text(
				for: "f",
				commandIsPressed: true,
				controlIsPressed: false
			) == nil
		)
		#expect(
			TypingRedirect.text(
				for: "\t",
				commandIsPressed: false,
				controlIsPressed: false
			) == nil
		)
	}
}
