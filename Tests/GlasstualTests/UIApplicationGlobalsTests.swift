/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 *********************************************************************** */

import Foundation
@testable import Glasstual
import Testing

/** A generator with no entropy in it, so a test can say what a "random" number
 has to be.

 `RandomNumberGenerator.next(upperBound:)` draws again while the draw is below a
 cutoff it derives from the bound, so a generator that keeps answering with the
 same small value never leaves that loop. Every value handed to one of these has
 to sit above the cutoff, and `.max` always does. */
private struct FixedRandomNumberGenerator: RandomNumberGenerator {
	var value: UInt64

	mutating func next() -> UInt64 {
		value
	}
}

/// Counts what is drawn from it, so a test can see that the draw reached the
/// generator the caller is holding.
private struct CountingRandomNumberGenerator: RandomNumberGenerator {
	private(set) var draws = 0

	mutating func next() -> UInt64 {
		draws += 1

		return .max - UInt64(draws)
	}
}

@Suite("Application globals")
struct UIApplicationGlobalsTests {
	/** The one ISO 8601 spelling the protocol layer writes: UTC, to the
	 millisecond, with the fraction always present.

	 It used to be one mutable `DateFormatter` the whole process reached for, so
	 anything that set `dateFormat` on it changed how every other timestamp
	 parsed; two callers cannot reach each other through a value. */
	@Test("The ISO spelling is UTC to the millisecond")
	func formatterWritesUTCMilliseconds() {
		let formatter = sharedISOStandardDateFormatter()

		#expect(formatter.string(from: Date(timeIntervalSince1970: 1_700_000_000.5))
			== "2023-11-14T22:13:20.500Z")
		#expect(formatter.string(from: Date(timeIntervalSince1970: 1_700_000_000))
			== "2023-11-14T22:13:20.000Z")
	}

	/** A millisecond figure is rarely exact in binary — the nearest `Double` to
	 `.123` sits just below it — and `Date.ISO8601FormatStyle` truncates the
	 fraction where the `DateFormatter` it replaced rounded it. Every MARKREAD,
	 CHATHISTORY and CTCP TIME stamp went out a millisecond early. */
	@Test("A fractional second is rounded rather than truncated")
	func fractionalSecondsAreRounded() {
		let formatter = sharedISOStandardDateFormatter()

		#expect(formatter.string(from: Date(timeIntervalSince1970: 1_700_000_000.123))
			== "2023-11-14T22:13:20.123Z")
		#expect(formatter.string(from: Date(timeIntervalSince1970: 1_700_000_000.001))
			== "2023-11-14T22:13:20.001Z")
		/* Rounding up through the second is still the right moment, and the
		 whole stamp moves with it. */
		#expect(formatter.string(from: Date(timeIntervalSince1970: 1_700_000_000.9999))
			== "2023-11-14T22:13:21.000Z")
	}

	@Test("The ISO representation round-trips, and only that representation parses")
	func formatterRoundTripsUTC() throws {
		let formatter = sharedISOStandardDateFormatter()
		let moment = Date(timeIntervalSince1970: 1_700_000_000.123)

		let text = formatter.string(from: moment)
		let parsed = try #require(formatter.date(from: text))

		#expect(abs(parsed.timeIntervalSince(moment)) < 0.001)
		#expect(text.hasSuffix("Z"))
		#expect(formatter.date(from: "14 November 2023") == nil)
		#expect(formatter.date(from: "") == nil)
	}

	/// The number is a function of the generator it is given, and the generator
	/// is taken the way the standard library takes one, so a draw advances the
	/// caller's own generator rather than a copy of it.
	@Test("A number below the maximum comes from the generator it was handed")
	func randomNumberUsesItsGenerator() {
		#expect(randomNumber(0) == 0)
		#expect(randomNumber(1) == 0)

		/* Two draws from equal generators have to agree, which is the whole of
		 what "a function of what it was handed" means; asserting the exact
		 number instead would pin how the standard library maps a draw onto a
		 range. */
		var first = FixedRandomNumberGenerator(value: .max)
		var second = FixedRandomNumberGenerator(value: .max)

		#expect(randomNumber(100, using: &first) == randomNumber(100, using: &second))
		#expect(randomNumber(100, using: &first) < 100)

		for _ in 0 ..< 100 {
			#expect(randomNumber(8) < 8)
		}
	}

	/// A generator that counts is what shows the draw reaching the caller's own
	/// generator: taken by value, the count stayed where it was.
	@Test("A draw advances the generator it was handed")
	func randomNumberAdvancesItsGenerator() {
		var generator = CountingRandomNumberGenerator()

		_ = randomNumber(100, using: &generator)

		#expect(generator.draws > 0)
	}
}
