/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 *
 *  * Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 *  * Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 *  * Neither the name of Textual, "Codeux Software, LLC", nor the
 *    names of its contributors may be used to endorse or promote products
 *    derived from this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED. IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
 * FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
 * OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
 * LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
 * OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
 * SUCH DAMAGE.
 *
 *********************************************************************** */

import Foundation
@testable import Glasstual
import Testing

/// The byte budget one IRC line has, and what happens when the framing alone
/// has already spent it.
struct IRCLineBudgetTests {
	@Test("A fresh budget has already been charged for the framing")
	func overheadIsChargedUpFront() {
		let budget = IRCLineBudget(overhead: 40, maximum: 510)

		#expect(budget.used == 40)
		#expect(budget.remaining == 470)
		#expect(budget.isOverBudget == false)
		#expect(budget.fits(470))
		#expect(budget.fits(471) == false)
	}

	@Test("Charging accumulates until the line is full")
	func chargingAccumulates() {
		var budget = IRCLineBudget(overhead: 10, maximum: 20)

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
		let budget = IRCLineBudget(overhead: 700, maximum: 510)

		#expect(budget.isOverBudget)
		#expect(budget.remaining == 0)
		#expect(budget.fits(0) == false)
		#expect(budget.fits(1) == false)
	}

	@Test("Negative counts are clamped rather than refunding bytes")
	func negativeCountsAreClamped() {
		var budget = IRCLineBudget(overhead: -5, maximum: -1)

		#expect(budget.overhead == 0)
		#expect(budget.maximum == 0)

		budget.charge(-10)

		#expect(budget.used == 0)
	}
}

@MainActor
struct IRCTextWrapBoundsTests {
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
struct IRCLineSplittingProgressTests {
	/// A long server-assigned hostmask plus a long channel name pushes the
	/// minimum length past the maximum, and the splitter then consumed
	/// nothing while the callers looped until the string was empty.
	@Test(.timeLimit(.minutes(1)))
	func splittingMakesProgressWhenTheBudgetIsAlreadyExhausted() {
		let client = GLTTestClient()
		client.userHostmask = String(repeating: "h", count: 400)

		let channelName = "#" + String(repeating: "c", count: 300)
		var cursor = IRCLineCursor(NSAttributedString(string: "hello world"))

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
		let client = GLTTestClient()
		client.userHostmask = "nick!user@host"

		var cursor = IRCLineCursor(NSAttributedString(string: "hello world"))
		let message = cursor.nextLine(forChannel: "#channel", on: client, with: .privateMessage)

		#expect(message == "hello world")
		#expect(cursor.isEmpty)
	}
}

@MainActor
struct IRCWireLengthBudgetTests {
	/// AWAYLEN, KICKLEN and TOPICLEN are byte budgets; an emoji is two UTF-16
	/// code units but four UTF-8 bytes.
	@Test
	func truncationCountsUTF8Bytes() {
		#expect(ClientWireUtilities.truncated("hello", toByteCount: 5) == "hello")
		#expect(ClientWireUtilities.truncated("hello", toByteCount: 4) == "hell")
		#expect(ClientWireUtilities.truncated("ab👍cd", toByteCount: 6) == "ab👍")
		#expect(ClientWireUtilities.truncated("ab👍cd", toByteCount: 5) == "ab")
	}

	@Test
	func aZeroBudgetMeansNoLimit() {
		#expect(ClientWireUtilities.truncated("hello", toByteCount: 0) == "hello")
	}

	@Test
	func truncationNeverSplitsACharacter() {
		let truncated = ClientWireUtilities.truncated("👍👍👍", toByteCount: 7)

		#expect(truncated == "👍")
		#expect(truncated.utf8.count <= 7)
	}
}
