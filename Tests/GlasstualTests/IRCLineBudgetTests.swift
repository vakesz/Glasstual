/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \\ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\\___/_/\\_\\__|\\__,_|\\__,_|_|
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

struct IRCTextWrapBoundsTests {
	/// The search window start was computed in unsigned arithmetic, so a
	/// result shorter than the distance underflowed into a large-negative
	/// NSRange location and raised an uncatchable NSRangeException.
	@Test(arguments: [0, 1, 5, 25, 26, 40])
	func wrappingAShortResultDoesNotRaise(_ length: Int) {
		let string = NSMutableString(string: String(repeating: "a", count: length))

		#expect(string.wrapIRCTextFormatterResult(with: 0, maxDistance: 26) == UInt(bitPattern: NSNotFound))
	}

	@Test
	func aZeroDistanceIsRefusedRatherThanTrapping() {
		let string = NSMutableString(string: "hello world")

		#expect(string.wrapIRCTextFormatterResult(with: 0, maxDistance: 0) == UInt(bitPattern: NSNotFound))
	}

	@Test
	func wrappingTrimsBackToTheLastSpace() {
		let string = NSMutableString(string: "hello there world")

		#expect(string.wrapIRCTextFormatterResult(with: 0, maxDistance: 26) == 6)
		#expect(string as String == "hello there")
	}

	@Test
	func aSpaceBeforeTheMinimumIndexIsNotUsed() {
		let string = NSMutableString(string: "hello world")

		#expect(string.wrapIRCTextFormatterResult(with: 8, maxDistance: 26) == UInt(bitPattern: NSNotFound))
		#expect(string as String == "hello world")
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
		let line = NSMutableAttributedString(string: "hello world")

		var iterations = 0

		while line.length > 0, iterations < 100 {
			_ = line.stringFormatted(forChannel: channelName, on: client, with: .privateMessage)
			iterations += 1
		}

		#expect(line.length == 0)
		#expect(iterations == 11)
	}

	@Test
	func splittingStillConsumesTheWholeLineWithAnOrdinaryBudget() {
		let client = GLTTestClient()
		client.userHostmask = "nick!user@host"

		let line = NSMutableAttributedString(string: "hello world")
		let message = line.stringFormatted(forChannel: "#channel", on: client, with: .privateMessage)

		#expect(message == "hello world")
		#expect(line.length == 0)
	}
}

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
