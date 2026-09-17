// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing

@Suite("Date formatting")
struct DateFormattingTests {
	/** The one ISO 8601 spelling the protocol layer writes: UTC, to the
	 millisecond, with the fraction always present.

	 It used to be one mutable `DateFormatter` the whole process reached for, so
	 anything that set `dateFormat` on it changed how every other timestamp
	 parsed; two callers cannot reach each other through a value. */
	@Test("The ISO spelling is UTC to the millisecond")
	func formatterWritesUTCMilliseconds() {
		#expect(DateFormatting.iso8601String(from: Date(timeIntervalSince1970: 1_700_000_000.5))
			== "2023-11-14T22:13:20.500Z")
		#expect(DateFormatting.iso8601String(from: Date(timeIntervalSince1970: 1_700_000_000))
			== "2023-11-14T22:13:20.000Z")
	}

	/** A millisecond figure is rarely exact in binary — the nearest `Double` to
	 `.123` sits just below it — and `Date.ISO8601FormatStyle` truncates the
	 fraction where the `DateFormatter` it replaced rounded it. Every MARKREAD,
	 CHATHISTORY and CTCP TIME stamp went out a millisecond early. */
	@Test("A fractional second is rounded rather than truncated")
	func fractionalSecondsAreRounded() {
		#expect(DateFormatting.iso8601String(from: Date(timeIntervalSince1970: 1_700_000_000.123))
			== "2023-11-14T22:13:20.123Z")
		#expect(DateFormatting.iso8601String(from: Date(timeIntervalSince1970: 1_700_000_000.001))
			== "2023-11-14T22:13:20.001Z")
		/* Rounding up through the second is still the right moment, and the
		 whole stamp moves with it. */
		#expect(DateFormatting.iso8601String(from: Date(timeIntervalSince1970: 1_700_000_000.9999))
			== "2023-11-14T22:13:21.000Z")
	}

	@Test("The ISO representation round-trips, and only that representation parses")
	func formatterRoundTripsUTC() throws {
		let moment = Date(timeIntervalSince1970: 1_700_000_000.123)

		let text = DateFormatting.iso8601String(from: moment)
		let parsed = try #require(DateFormatting.date(fromISO8601: text))

		#expect(abs(parsed.timeIntervalSince(moment)) < 0.001)
		#expect(text.hasSuffix("Z"))
		#expect(DateFormatting.date(fromISO8601: "14 November 2023") == nil)
		#expect(DateFormatting.date(fromISO8601: "") == nil)
	}
}
