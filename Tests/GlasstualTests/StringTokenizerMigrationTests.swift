/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import CocoaExtensions
import Foundation
import XCTest

final class StringTokenizerMigrationTests: XCTestCase {
	func testWhitespaceTokenReportsUTF16Ranges() {
		let source: NSString = "JOIN    #swift"
		var capturedToken: String?
		var capturedTokenRange = NSRange(location: NSNotFound, length: 0)
		var capturedDeletionRange = NSRange(location: NSNotFound, length: 0)

		source.ce_getTokenFromWhitespaceGroup { token, tokenRange, deletionRange in
			capturedToken = token
			capturedTokenRange = tokenRange
			capturedDeletionRange = deletionRange
		}

		XCTAssertEqual(capturedToken, "JOIN")
		XCTAssertEqual(capturedTokenRange, NSRange(location: 0, length: 4))
		XCTAssertEqual(capturedDeletionRange, NSRange(location: 0, length: 8))
	}

	func testMutableStringConsumesWhitespaceAndQuotedTokens() {
		let command = NSMutableString(string: "PRIVMSG   #swift")
		XCTAssertEqual(command.ce_uppercaseToken, "PRIVMSG")
		XCTAssertEqual(command, "#swift")

		let quoted = NSMutableString(string: #""one\" two"   tail"#)
		XCTAssertEqual(quoted.ce_tokenInsideQuotes, #"one" two"#)
		XCTAssertEqual(quoted, "tail")
	}

	func testQuoteTokenHonorsSingleQuoteAndTerminationOptions() {
		let singleQuoted: NSString = "'one two' next"
		var token: String?
		singleQuoted.ce_getTokenFromQuoteGroup({ value, _, deletionRange in
			token = value
			XCTAssertEqual(deletionRange, NSRange(location: 0, length: 10))
		}, options: (1 << 1) | (1 << 2) | (1 << 3))
		XCTAssertEqual(token, "one two")

		let invalid = NSMutableString(string: #""value"suffix"#)
		XCTAssertEqual(invalid.ce_tokenInsideQuotes, "")
		XCTAssertEqual(invalid, #""value"suffix"#)
	}

	func testAttributedTokenPreservesAttributesAndConsumesSource() throws {
		let marker = NSAttributedString.Key("StringTokenizerMigrationMarker")
		let source = NSMutableAttributedString(
			string: "JOIN   #swift",
			attributes: [marker: "preserved"]
		)

		let token = source.ce_token

		XCTAssertEqual(token.string, "JOIN")
		XCTAssertEqual(try XCTUnwrap(token.attribute(marker, at: 0, effectiveRange: nil) as? String), "preserved")
		XCTAssertEqual(source.string, "#swift")
	}

	func testEmptyInputReturnsInvalidRangesWithoutMutation() {
		let source: NSString = ""
		source.ce_getTokenFromWhitespaceGroup { token, tokenRange, deletionRange in
			XCTAssertNil(token)
			XCTAssertEqual(tokenRange.location, NSNotFound)
			XCTAssertEqual(deletionRange.location, NSNotFound)
		}
	}
}
