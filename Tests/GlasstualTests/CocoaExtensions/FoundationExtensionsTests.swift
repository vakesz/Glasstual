// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation
import Testing

@Suite("Foundation value formatting")
@MainActor
struct FoundationExtensionsTests {
	@Test("A one-digit number gains a leading zero")
	func integersGainALeadingZero() {
		#expect(NSNumber(value: 7).twoDigitString == "07")
		#expect(NSNumber(value: 42).twoDigitString == "42")
		#expect(NSNumber(value: 1234).twoDigitString == "1234")
	}
}
