// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Testing

/** Flood control promises what its two settings say: no more than the maximum
 number of lines in any span of the interval, wherever that span starts. */
@Suite("Flood-control window")
nonisolated struct FloodControlWindowTests {
	private static let origin = ContinuousClock.now

	private static func at(_ milliseconds: Int) -> ContinuousClock.Instant {
		origin + .milliseconds(milliseconds)
	}

	@Test("Lines up to the maximum go out together, and the next one waits")
	func capacityIsAdmittedAtOnce() {
		var window = FloodControlWindow(capacity: 6, interval: .seconds(2))

		for _ in 0 ..< 6 {
			#expect(window.admits(at: Self.at(0)))
			window.record(at: Self.at(0))
		}

		#expect(window.admits(at: Self.at(0)) == false)
		#expect(window.nextAdmission() == Self.at(2000))
		#expect(window.admits(at: Self.at(1999)) == false)
		#expect(window.admits(at: Self.at(2000)))
	}

	/// The edge a fixed window gets wrong: a full allowance just before a tick
	/// used to be followed by a second one just after it.
	@Test("A full allowance at the end of one interval is not followed by another at the start of the next")
	func noDoubleAllowanceAcrossABoundary() {
		var window = FloodControlWindow(capacity: 6, interval: .seconds(2))

		for _ in 0 ..< 6 {
			#expect(window.admits(at: Self.at(1999)))
			window.record(at: Self.at(1999))
		}

		#expect(window.admits(at: Self.at(2001)) == false)
		#expect(window.nextAdmission() == Self.at(3999))
		#expect(window.admits(at: Self.at(3999)))
	}

	@Test("A line put back gives its slot back")
	func forgetLatestReturnsASlot() {
		var window = FloodControlWindow(capacity: 2, interval: .seconds(2))
		window.record(at: Self.at(0))
		window.record(at: Self.at(10))

		#expect(window.admits(at: Self.at(20)) == false)
		window.forgetLatest()
		#expect(window.recordedCount == 1)
		#expect(window.admits(at: Self.at(20)))
		#expect(window.nextAdmission() == nil)
	}

	@Test("Reset empties the window")
	func resetEmptiesTheWindow() {
		var window = FloodControlWindow(capacity: 1, interval: .seconds(60))
		window.record(at: Self.at(0))

		#expect(window.admits(at: Self.at(1)) == false)
		window.reset()
		#expect(window.recordedCount == 0)
		#expect(window.admits(at: Self.at(1)))
	}

	@Test("A capacity below one still lets one line through")
	func capacityIsAtLeastOne() {
		let window = FloodControlWindow(capacity: 0, interval: .seconds(2))

		#expect(window.capacity == 1)
		#expect(window.admits(at: Self.at(0)))
	}

	nonisolated struct Pattern: Sendable, CustomTestStringConvertible {
		let capacity: Int
		let intervalMilliseconds: Int
		/// When each line is queued, in milliseconds from the start.
		let arrivals: [Int]

		var testDescription: String {
			"\(capacity) per \(intervalMilliseconds) ms, \(arrivals.count) lines"
		}
	}

	private static let patterns: [Pattern] = {
		// A fixed linear congruential sequence, so every run checks the same arrivals.
		var state: UInt64 = 0x2545_F491_4F6C_DD1D
		func nextArrival() -> Int {
			state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
			return Int((state >> 33) % 10001)
		}
		var patterns = [
			Pattern(capacity: 6, intervalMilliseconds: 2000, arrivals: Array(repeating: 0, count: 40)),
			Pattern(
				capacity: 6,
				intervalMilliseconds: 2000,
				arrivals: Array(repeating: 1999, count: 12) + Array(repeating: 2001, count: 12)
			),
			Pattern(capacity: 1, intervalMilliseconds: 60000, arrivals: [0, 1, 59999, 60000, 60001]),
			Pattern(capacity: 60, intervalMilliseconds: 1000, arrivals: (0 ..< 300).map { $0 * 7 }),
		]
		for capacity in [1, 3, 6, 10] {
			let arrivals = (0 ..< 120).map { _ in nextArrival() }.sorted()
			patterns.append(Pattern(capacity: capacity, intervalMilliseconds: 2000, arrivals: arrivals))
		}
		return patterns
	}()

	/** A sender that writes every queued line the moment the window admits it,
	 and otherwise waits exactly until ``FloodControlWindow/nextAdmission()``,
	 as the connection host does. Every span of one interval is then checked. */
	@Test("A greedy sender never puts more than the maximum in any interval", arguments: patterns)
	func greedySenderRespectsEveryInterval(pattern: Pattern) throws {
		var window = FloodControlWindow(capacity: pattern.capacity, interval: .milliseconds(pattern.intervalMilliseconds))
		var pending = pattern.arrivals.sorted()[...]
		var now = Self.at(0)
		var sends: [ContinuousClock.Instant] = []

		while let arrival = pending.first {
			now = max(now, Self.at(arrival))
			if window.admits(at: now) {
				window.record(at: now)
				sends.append(now)
				pending.removeFirst()
			} else {
				now = try #require(window.nextAdmission())
			}
		}

		#expect(sends.count == pattern.arrivals.count)
		let interval = Duration.milliseconds(pattern.intervalMilliseconds)
		for (index, start) in sends.enumerated() {
			let inSpan = sends[index...].prefix { $0 < start + interval }.count
			#expect(inSpan <= pattern.capacity, "\(inSpan) lines in the interval from send \(index)")
		}
	}
}
