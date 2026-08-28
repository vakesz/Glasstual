/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import CocoaExtensions
import Foundation
import Testing

/// The `String` helpers that replaced the `ce_`-prefixed `NSString` category.
@Suite("String helper")
struct StringHelperTests {
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
		#expect("DEADBEEF".onlyContainsCharacters(from: .textualHexadecimal))
		#expect("DEADBEEG".onlyContainsCharacters(from: .textualHexadecimal) == false)
		#expect("host-1.example.test".onlyContainsCharacters(from: .textualAlphanumericDashPeriod))
		#expect("host/1".onlyContainsCharacters(from: .textualAlphanumericDashPeriod) == false)
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

	@Test("Each searched character starts where the last match ended")
	func occurrenceRangesAdvance() {
		let ranges = "banana".rangesOfFirstOccurrences(ofCharactersIn: "an", options: [])

		#expect(ranges.map(\.location) == [1, 2])
	}

	@Test("Scanning stops at the first character that is missing")
	func occurrenceRangesStopOnMiss() {
		#expect("banana".rangesOfFirstOccurrences(ofCharactersIn: "az", options: []).count == 1)
		#expect("".rangesOfFirstOccurrences(ofCharactersIn: "a", options: []).isEmpty)
	}

	@Test("Case-insensitive scanning is what the spotlight table asks for")
	func occurrenceRangesHonorOptions() {
		let ranges = "Glasstual".rangesOfFirstOccurrences(ofCharactersIn: "gl", options: .caseInsensitive)

		#expect(ranges.map(\.location) == [0, 1])
	}

	@Test("Truncation cuts on a character boundary")
	func truncationRespectsCharacters() {
		#expect("abc".truncated(toUTF8Bytes: 10) == "abc")
		#expect("aあb".truncated(toUTF8Bytes: 3) == "a")
		#expect("aあb".truncated(toUTF8Bytes: 4) == "aあ")
	}

	@Test("An encoding resolves to its IANA name")
	func encodingsCarryCharsetNames() {
		#expect(String.Encoding.ianaCharsetName(forRawValue: String.Encoding.utf8.rawValue) == "utf-8")
		#expect(String.Encoding.ianaCharsetName(forRawValue: 0) == nil)
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

/// The two attributed-string helpers that survived the fold.
@Suite("Attributed string helper")
struct AttributedStringHelperTests {
	private let marker = NSAttributedString.Key("StringHelperTestsMarker")

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
