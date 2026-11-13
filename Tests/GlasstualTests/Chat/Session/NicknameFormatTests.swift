// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
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

	@Test("The parsed format matches the Scanner-based reading for odd formats", arguments: [
		"%@%n:", "", "%", "%%", "%%%", "a%", "%x", "%5x", "%-x", "%+5n", "%-5n%@", "%05n", "%-0n",
		"%3@|%n", "100%", "%n%n", "%12", "%-", "é%4nü", "%9223372036854775807n",
		"%99999999999999999999999n", "%-99999999999999999999999n", "%300n", "%-300@", "%5%"
	])
	func parsedFormatMatchesScannerReading(format: String) {
		for nickname in ["alice", "🦊", ""] {
			#expect(
				NicknameFormat.apply(nickname, modeSymbol: "@", format: format)
					== Self.scannerReading(nickname, modeSymbol: "@", format: format)
			)
		}
	}

	@Test("A changed format is not served from the previous parse")
	func changedFormatIsReparsed() {
		#expect(NicknameFormat.apply("a", modeSymbol: "", format: "<%n>") == "<a>")
		#expect(NicknameFormat.apply("a", modeSymbol: "", format: "[%n]") == "[a]")
		#expect(NicknameFormat.apply("a", modeSymbol: "", format: "<%n>") == "<a>")
	}

	/// The previous implementation, kept as the reference for the parsed one.
	private static func scannerReading(_ nickname: String, modeSymbol: String, format: String) -> String {
		let scanner = Scanner(string: format)
		scanner.charactersToBeSkipped = nil
		var output = ""
		while scanner.isAtEnd == false {
			if let literal = scanner.scanUpToString("%") {
				output += literal
			}
			guard scanner.scanString("%") != nil else { break }
			let paddingWidth = scanner.scanInt() ?? 0
			let substitution: String? = if scanner.scanString("@") != nil {
				modeSymbol
			} else if scanner.scanString("n") != nil {
				nickname
			} else if scanner.scanString("%") != nil {
				"%"
			} else {
				nil
			}
			guard let substitution else { continue }
			let length = (substitution as NSString).length
			let requested = Int(min(paddingWidth.magnitude, 256))
			let padding = String(repeating: " ", count: max(0, requested - length))
			if paddingWidth < 0 {
				output += padding
			}
			output += substitution
			if paddingWidth > 0 {
				output += padding
			}
		}
		return output
	}
}
