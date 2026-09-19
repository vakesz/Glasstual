// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

@testable import Glasstual
import Testing

@MainActor
@Suite("Nickname formatting")
struct NicknameFormatTests {
	@Test("Nickname formatting keeps the mode marker and pads in UTF-16 units")
	func nicknameFormattingPreservesMarkersAndUTF16Padding() {
		#expect(
			NicknameFormat.apply("alice", modeSymbol: "@", format: "[%@%8n] %%")
				== "[@alice   ] %"
		)
		#expect(
			NicknameFormat.apply("🦊", modeSymbol: "", format: "%3n") == "🦊 "
		)
		#expect(
			NicknameFormat.apply("bob", modeSymbol: "+", format: "%-5n%@") == "  bob+"
		)
	}

	/// `scanInt()` yields Int.min for this format, and `abs(Int.min)` traps.
	@Test("An extreme negative padding width does not trap")
	func extremeNegativePaddingDoesNotTrap() {
		let formatted = NicknameFormat.apply(
			"nick",
			modeSymbol: "@",
			format: "%-9223372036854775808n"
		)

		#expect(formatted.hasSuffix("nick"))
	}
}
