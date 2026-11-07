// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing

/// How many unsolicited offers one connection takes inside the window.
struct DCCOfferThrottleTests {
	private let start = Date(timeIntervalSince1970: 1_700_000_000)

	@Test("One sender gets three offers a window")
	func perSenderLimit() {
		var throttle = DCCOfferThrottle()

		let results = (0 ..< 5).map { _ in throttle.recordOffer(from: "mara", at: start) }

		#expect(results == [true, true, true, false, false])
		#expect(DCCOfferThrottle.perSenderLimit == 3)
	}

	@Test("Another sender is counted on their own")
	func sendersAreIndependent() {
		var throttle = DCCOfferThrottle()
		for _ in 0 ..< 3 {
			_ = throttle.recordOffer(from: "mara", at: start)
		}

		#expect(throttle.recordOffer(from: "mara", at: start) == false)
		let admitted1 = throttle.recordOffer(from: "ines", at: start)
		#expect(admitted1)
	}

	@Test("Everyone together gets ten offers a window")
	func overallLimit() {
		var throttle = DCCOfferThrottle()
		let senders = ["a", "b", "c", "d"]
		var admitted = 0

		for sender in senders {
			for _ in 0 ..< 3 where throttle.recordOffer(from: sender, at: start) {
				admitted += 1
			}
		}

		#expect(admitted == DCCOfferThrottle.overallLimit)
		#expect(throttle.recordOffer(from: "e", at: start) == false)
	}

	@Test("An offer stops counting once a full window has passed")
	func windowSlides() {
		var throttle = DCCOfferThrottle()
		for _ in 0 ..< 3 {
			_ = throttle.recordOffer(from: "mara", at: start)
		}

		#expect(throttle.recordOffer(from: "mara", at: start.addingTimeInterval(DCCOfferThrottle.window - 0.1)) == false)
		let admittedAfterWindow = throttle.recordOffer(from: "mara", at: start.addingTimeInterval(DCCOfferThrottle.window))
		#expect(admittedAfterWindow)
	}

	@Test("Tracked senders are bounded")
	func trackedSenderCeiling() {
		#expect(DCCOfferThrottle.maximumTrackedSenders == 64)
		#expect(DCCOfferThrottle.maximumTrackedSenders > DCCOfferThrottle.overallLimit)
	}
}
