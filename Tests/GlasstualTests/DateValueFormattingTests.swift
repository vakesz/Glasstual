/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import Foundation
@testable import Glasstual
import Testing

@Suite("Date value formatting")
@MainActor
struct DateValueFormattingTests {
	@Test("A Date is formatted")
	func formatsDate() {
		let formatted = DateFormatting.formatted(Date(timeIntervalSince1970: 0), dateStyle: .long, timeStyle: .long, relative: false)

		#expect(formatted.isEmpty == false)
	}

	@Test("An ISO 8601 string is parsed before it is formatted")
	func formatsISOString() throws {
		let formatted = try #require(DateFormatting.formatted(
			serverText: "2024-03-05T12:30:00.000Z",
			dateStyle: .long,
			timeStyle: .long,
			relative: false
		))

		#expect(formatted.contains("2024"))
		// The raw server text must not simply be echoed back.
		#expect(formatted != "2024-03-05T12:30:00.000Z")
	}

	@Test("A Unix timestamp string is parsed before it is formatted")
	func formatsEpochString() throws {
		let formatted = try #require(DateFormatting.formatted(
			serverText: "1709641800",
			dateStyle: .long,
			timeStyle: .long,
			relative: false
		))

		#expect(formatted.contains("2024"))
	}

	@Test("An unparseable string yields nil so callers can show it verbatim")
	func rejectsUnparseableString() {
		#expect(DateFormatting.formatted(serverText: "not a date", dateStyle: .long, timeStyle: .long, relative: false) == nil)
	}

	/// `TimeInterval("inf")` and `TimeInterval("nan")` both parse, so a server
	/// that sends one would otherwise be believed and formatted as a moment.
	@Test(
		"A numeric string that is not a moment yields nil",
		arguments: ["inf", "-inf", "infinity", "nan", "1e400"]
	)
	func rejectsNonFiniteEpochString(_ text: String) {
		#expect(DateFormatting.formatted(serverText: text, dateStyle: .long, timeStyle: .long, relative: false) == nil)
	}
}
