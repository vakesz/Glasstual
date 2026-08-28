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
		let formatted = formatDateLongStyle(Date(timeIntervalSince1970: 0) as Any, false)

		#expect(formatted?.isEmpty == false)
	}

	@Test("An ISO 8601 string is parsed before it is formatted")
	func formatsISOString() throws {
		let formatted = try #require(formatDateLongStyle("2024-03-05T12:30:00.000Z" as Any, false))

		#expect(formatted.contains("2024"))
		// The raw server text must not simply be echoed back.
		#expect(formatted != "2024-03-05T12:30:00.000Z")
	}

	@Test("A Unix timestamp string is parsed before it is formatted")
	func formatsEpochString() throws {
		let formatted = try #require(formatDateLongStyle("1709641800" as Any, false))

		#expect(formatted.contains("2024"))
	}

	@Test("An unparseable string yields nil so callers can show it verbatim")
	func rejectsUnparseableString() {
		#expect(formatDateLongStyle("not a date" as Any, false) == nil)
	}
}
