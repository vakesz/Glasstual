// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

@testable import Glasstual
import Testing

@Suite("draft/multiline limits")
struct MultilineLimitsTests {
	@Test("Both limits are read from the capability value")
	func readsBothLimits() {
		let limits = MultilineLimits(capabilityValues: ["max-bytes=4096", "max-lines=100"])

		#expect(limits == MultilineLimits(maximumBytes: 4096, maximumLines: 100))
	}

	@Test("A missing line limit means the server set none")
	func lineLimitIsOptional() {
		let limits = MultilineLimits(capabilityValues: ["max-bytes=1024"])

		#expect(limits?.maximumBytes == 1024)
		#expect(limits?.maximumLines == nil)
	}

	@Test("A value without a usable byte limit cannot be used", arguments: [
		[String](),
		["max-lines=10"],
		["max-bytes=0"],
		["max-bytes=-5"],
		["max-bytes=many"],
		["max-bytes"],
	])
	func unusableValues(_ values: [String]) {
		#expect(MultilineLimits(capabilityValues: values) == nil)
	}

	@Test("Unknown keys and unusable line limits are skipped")
	func skipsWhatItDoesNotKnow() {
		let limits = MultilineLimits(capabilityValues: ["max-bytes=512", "max-lines=0", "future=1", "max-lines=x"])

		#expect(limits == MultilineLimits(maximumBytes: 512, maximumLines: nil))
	}
}
