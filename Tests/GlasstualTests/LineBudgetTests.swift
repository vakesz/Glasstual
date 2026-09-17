// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing

/// The byte budget one IRC line has, and what happens when the framing alone
/// has already spent it.
struct LineBudgetTests {
	@Test("A fresh budget has already been charged for the framing")
	func overheadIsChargedUpFront() {
		let budget = LineBudget(overhead: 40, maximum: 510)

		#expect(budget.used == 40)
		#expect(budget.remaining == 470)
		#expect(budget.isOverBudget == false)
		#expect(budget.fits(470))
		#expect(budget.fits(471) == false)
	}

	@Test("Charging accumulates until the line is full")
	func chargingAccumulates() {
		var budget = LineBudget(overhead: 10, maximum: 20)

		budget.charge(5)

		#expect(budget.used == 15)
		#expect(budget.remaining == 5)
		#expect(budget.isOverBudget == false)

		budget.charge(6)

		#expect(budget.isOverBudget)
		#expect(budget.remaining == 0)
	}

	/// A server-assigned hostmask plus a long channel name can make the framing
	/// alone longer than the whole line. In unsigned arithmetic the remainder
	/// wrapped to four billion and the splitter believed it had room for
	/// everything.
	@Test("Framing longer than the line reads as exhausted, not as unlimited")
	func overheadPastTheMaximumIsExhausted() {
		let budget = LineBudget(overhead: 700, maximum: 510)

		#expect(budget.isOverBudget)
		#expect(budget.remaining == 0)
		#expect(budget.fits(0) == false)
		#expect(budget.fits(1) == false)
	}

	@Test("Negative counts are clamped rather than refunding bytes")
	func negativeCountsAreClamped() {
		var budget = LineBudget(overhead: -5, maximum: -1)

		#expect(budget.overhead == 0)
		#expect(budget.maximum == 0)

		budget.charge(-10)

		#expect(budget.used == 0)
	}
}

@MainActor
struct TextWrapBoundsTests {
	/// The search window start was computed in unsigned arithmetic, so a
	/// result shorter than the distance underflowed into a large-negative
	/// NSRange location and raised an uncatchable NSRangeException.
	@Test(arguments: [0, 1, 5, 25, 26, 40])
	func wrappingAShortResultDoesNotRaise(_ length: Int) {
		var string = String(repeating: "a", count: length)

		#expect(string.wrapIRCTextFormatterResult(with: 0, maxDistance: 26) == UInt(bitPattern: NSNotFound))
	}

	@Test
	func aZeroDistanceIsRefusedRatherThanTrapping() {
		var string = "hello world"

		#expect(string.wrapIRCTextFormatterResult(with: 0, maxDistance: 0) == UInt(bitPattern: NSNotFound))
	}

	@Test
	func wrappingTrimsBackToTheLastSpace() {
		var string = "hello there world"

		#expect(string.wrapIRCTextFormatterResult(with: 0, maxDistance: 26) == 6)
		#expect(string == "hello there")
	}

	@Test
	func aSpaceBeforeTheMinimumIndexIsNotUsed() {
		var string = "hello world"

		#expect(string.wrapIRCTextFormatterResult(with: 8, maxDistance: 26) == UInt(bitPattern: NSNotFound))
		#expect(string == "hello world")
	}
}

@MainActor
struct LineSplittingProgressTests {
	/// A long server-assigned hostmask plus a long channel name pushes the
	/// minimum length past the maximum, and the splitter then consumed
	/// nothing while the callers looped until the string was empty.
	@Test(.timeLimit(.minutes(1)))
	func splittingMakesProgressWhenTheBudgetIsAlreadyExhausted() {
		let client = TestClient()
		client.userHostmask = String(repeating: "h", count: 400)

		let channelName = "#" + String(repeating: "c", count: 300)
		var cursor = LineCursor(NSAttributedString(string: "hello world"))

		var iterations = 0

		while cursor.isEmpty == false, iterations < 100 {
			_ = cursor.nextLine(forChannel: channelName, on: client, with: .privateMessage)
			iterations += 1
		}

		#expect(cursor.isEmpty)
		#expect(iterations == 11)
	}

	@Test
	func splittingStillConsumesTheWholeLineWithAnOrdinaryBudget() {
		let client = TestClient()
		client.userHostmask = "nick!user@host"

		var cursor = LineCursor(NSAttributedString(string: "hello world"))
		let message = cursor.nextLine(forChannel: "#channel", on: client, with: .privateMessage)

		#expect(message == "hello world")
		#expect(cursor.isEmpty)
	}
}

@MainActor
struct WireLengthBudgetTests {
	/// AWAYLEN, KICKLEN and TOPICLEN are byte budgets; an emoji is two UTF-16
	/// code units but four UTF-8 bytes.
	@Test
	func truncationCountsUTF8Bytes() {
		#expect(ProtocolLimits.truncated("hello", toByteCount: 5) == "hello")
		#expect(ProtocolLimits.truncated("hello", toByteCount: 4) == "hell")
		#expect(ProtocolLimits.truncated("ab👍cd", toByteCount: 6) == "ab👍")
		#expect(ProtocolLimits.truncated("ab👍cd", toByteCount: 5) == "ab")
	}

	@Test
	func aZeroBudgetMeansNoLimit() {
		#expect(ProtocolLimits.truncated("hello", toByteCount: 0) == "hello")
	}
}
