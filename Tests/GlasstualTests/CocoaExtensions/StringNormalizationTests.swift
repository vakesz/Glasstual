// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation
import Testing

/// The `String` helpers that replaced the `ce_`-prefixed `NSString` category.
@Suite("String normalization")
struct StringNormalizationTests {
	@Test("Zero-width spaces are dropped and space-alikes fold to U+0020")
	func spacesAreNormalized() {
		#expect("A\u{200B}B\u{2009}C".normalizingSpaces == "AB C")
		#expect("A\u{00A0}B".normalizingSpaces == "A B")
		#expect("A\u{3000}B".normalizingSpaces == "A B")
		#expect("".normalizingSpaces == "")
	}

	@Test("A non-BMP space folds too, which the UTF-16 scan could not reach")
	func astralSpaceIsNormalized() {
		#expect("A\u{E0020}B".normalizingSpaces == "A B")
	}

	@Test("An ordinary string is returned unchanged")
	func ordinaryStringsAreUntouched() {
		#expect("hello world".normalizingSpaces == "hello world")
		#expect("😀 IRC".normalizingSpaces == "😀 IRC")
	}

	@Test("A home-directory path is abbreviated to a tilde")
	func homePathBecomesTilde() {
		let home = FileManager.pathOfHomeDirectoryOutsideSandbox

		#expect(home.standardizedTildePath == "~")
		#expect((home + "/Documents").standardizedTildePath == "~/Documents")
	}

	@Test("A path outside the home directory is left alone")
	func foreignPathIsUnchanged() {
		#expect("/usr/local/bin".standardizedTildePath == "/usr/local/bin")
	}

	@Test("A sibling directory sharing the home prefix is not abbreviated")
	func siblingOfHomeIsNotAbbreviated() {
		let home = FileManager.pathOfHomeDirectoryOutsideSandbox
		let sibling = home + "Extra"

		#expect(sibling.standardizedTildePath == sibling)
	}

	@Test("Membership is tested per scalar")
	func characterMembershipIsChecked() {
		#expect("DEADBEEF".onlyContainsCharacters(from: .hexadecimalDigits))
		#expect("DEADBEEG".onlyContainsCharacters(from: .hexadecimalDigits) == false)
		#expect("host-1.example.test".onlyContainsCharacters(from: .hostNameCharacters))
		#expect("host/1".onlyContainsCharacters(from: .hostNameCharacters) == false)
	}

	@Test("Only unreserved URI characters survive percent encoding")
	func percentEncodingKeepsUnreservedCharacters() {
		#expect("Glasstual IRC".percentEncoded == "Glasstual%20IRC")
		#expect("a/b?c".percentEncoded == "a%2Fb%3Fc")
		#expect("safe-._~".percentEncoded == "safe-._~")
	}

	@Test("A prefix match outscores a scattered one")
	func matchScoreRanksPrefixesHigher() {
		let prefix = "#glasstual".matchScore(against: "glass", lengthPenaltyWeight: 0.1)
		let scattered = "#glasstual".matchScore(against: "gsul", lengthPenaltyWeight: 0.1)

		#expect(prefix > scattered)
		#expect(scattered > 0)
	}

	@Test("A word that is not a subsequence scores zero")
	func matchScoreRejectsNonSubsequences() {
		#expect("#glasstual".matchScore(against: "zzz", lengthPenaltyWeight: 0.1) == 0)
		#expect("#irc".matchScore(against: "", lengthPenaltyWeight: 0.1) == 0)
		/* The candidate cannot be longer than the receiver. */
		#expect("#irc".matchScore(against: "#ircnetwork", lengthPenaltyWeight: 0.1) == 0)
	}

	@Test("Matching ignores case")
	func matchScoreIgnoresCase() {
		#expect("#Glasstual".matchScore(against: "GLASS", lengthPenaltyWeight: 0.1) > 0)
	}

	@Test("Truncation cuts on a character boundary")
	func truncationRespectsCharacters() {
		#expect("abc".truncated(toUTF8Bytes: 10) == "abc")
		#expect("aあb".truncated(toUTF8Bytes: 3) == "a")
		#expect("aあb".truncated(toUTF8Bytes: 4) == "aあ")
	}

	@Test("The encoding table is keyed by localized name and favours UTF-8")
	func encodingTableIsKeyedByTitle() {
		let favored = String.Encoding.supportedEncodings(favoringUTF8: true)
		let utf8 = NSNumber(value: String.Encoding.utf8.rawValue)

		#expect(favored.first == utf8)
		#expect(favored.filter { $0 == utf8 }.count == 1)

		let table = String.Encoding.supportedEncodingsByTitle(favoringUTF8: true)
		let utf8Title = String.localizedName(of: .utf8)

		#expect(table[utf8Title] == utf8)
	}
}
