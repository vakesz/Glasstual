/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import CocoaExtensions
import Foundation
@testable import Glasstual
import XCTest

@MainActor
final class FrameworkStringHelperMigrationTests: XCTestCase {
	func testHashesMatchPublishedDigests() {
		let source: NSString = "abc"

		XCTAssertEqual(source.ceSha1, "a9993e364706816aba3e25717850c26c9cd0d89d")
		XCTAssertEqual(source.ceSha256, "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
		XCTAssertEqual(
			source.ceSha512,
			"ddaf35a193617abacc417349ae204131" +
				"12e6fa4e89a97ea20a9eeee64b55d39a" +
				"2192992a274fc1a836ba3c23a3feebbd" +
				"454d4423643ce80e2a9ac94fa54ca49f"
		)
	}

	func testSubstringAndSplitLengthsUseUTF16CodeUnits() {
		let source: NSString = "A😀BC"

		XCTAssertEqual(source.ceRange, NSRange(location: 0, length: 5))
		XCTAssertEqual(source.ce_substring(from: 1, to: 3), "😀")
		XCTAssertEqual(source.ce_split(maximumLength: 3), ["A😀", "BC"])
	}

	func testCaseInsensitiveSelectorsKeepNSStringSpecialization() {
		let source: NSString = "Glasstual"

		XCTAssertTrue(source.ce_isEqualToStringIgnoringCase("glasstual"))
		XCTAssertTrue(source.responds(to: NSSelectorFromString("isEqualIgnoringCase:")))
		XCTAssertTrue(source.responds(to: NSSelectorFromString("containsIgnoringCase:")))
	}

	func testIPParsingReturnsNetworkBytes() {
		XCTAssertEqual(("127.0.0.1" as NSString).ceIPv4AddressBytes, Data([127, 0, 0, 1]))
		XCTAssertEqual(
			("2001:db8::1" as NSString).ceIPv6AddressBytes,
			Data([0x20, 0x01, 0x0D, 0xB8, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1])
		)
		XCTAssertNil(("999.0.0.1" as NSString).ceIPv4AddressBytes)
		XCTAssertTrue(("::1" as NSString).ceIsIPAddress)
	}

	func testFormDataAndSpaceNormalizationPreserveLegacyRules() {
		let form = ("name=Glasstual%20IRC&flag&name=latest" as NSString).ceURLQueryItems

		XCTAssertEqual(form, ["name": "latest", "flag": ""])
		XCTAssertEqual(("A\u{200B}B\u{2009}C" as NSString).ceNormalizeSpaces, "AB C")
		XCTAssertEqual(("😀\nIRC" as NSString).ceRemoveAllNewlines, "😀IRC")
	}

	func testAttributedLineSplittingPreservesUTF16RangesAndAttributes() throws {
		let marker = NSAttributedString.Key("FrameworkStringHelperMigrationMarker")
		let source = NSAttributedString(string: "😀 one\ntwo", attributes: [marker: "kept"])

		let lines = source.ceSplitIntoLines

		XCTAssertEqual(lines.map(\.string), ["😀 one", "two"])
		XCTAssertEqual(try XCTUnwrap(lines[1].attribute(marker, at: 0, effectiveRange: nil) as? String), "kept")
	}

	func testMutableAttributedHelpersApplyFromUTF16Index() {
		let marker = NSAttributedString.Key("FrameworkStringHelperMigrationMarker")
		let source = NSMutableAttributedString(string: "A😀B")

		source.ce_addAttribute(marker.rawValue, value: "marked", startingAt: 3)

		XCTAssertNil(source.attribute(marker, at: 2, effectiveRange: nil))
		XCTAssertEqual(source.attribute(marker, at: 3, effectiveRange: nil) as? String, "marked")
		source.ce_resetAttributes(startingAt: 3)
		XCTAssertNil(source.attribute(marker, at: 3, effectiveRange: nil))
	}
}
