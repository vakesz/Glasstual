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

struct IRCLineParserNumericTests {
	/// `Int32(numeric)` trapped on the error path for an oversized numeric,
	/// and the numeric itself came from a saturating `integerValue`.
	@Test(arguments: ["99999999999", "1000", "0001", "12", "1"])
	func numericsOutsideThreeDigitsAreNotNumerics(_ command: String) throws {
		let line = try #require(LineParser.parsedLine(fromLine: ":srv \(command) nick :x"))

		#expect(line.commandNumeric == 0)
		#expect(line.command == command)
	}

	@Test(arguments: [("001", UInt(1)), ("353", UInt(353)), ("999", UInt(999))])
	func threeDigitNumericsAreParsed(_ command: String, _ expected: UInt) throws {
		let line = try #require(LineParser.parsedLine(fromLine: ":srv \(command) nick :x"))

		#expect(line.commandNumeric == expected)
	}

	/// `CharacterSet.decimalDigits` also matches non-ASCII digits, which
	/// `integerValue` then read as zero while the command stayed unshifted.
	@Test
	func nonASCIIDigitsAreNotNumerics() throws {
		let line = try #require(LineParser.parsedLine(fromLine: ":srv \u{0661}\u{0662}\u{0663} nick :x"))

		#expect(line.commandNumeric == 0)
	}

	@Test
	func malformedMessageStringSurvivesAnOversizedNumeric() {
		#expect(IRCDiagnosticStrings.malformedMessage(numeric: 99_999_999_999, sequence: "x").isEmpty == false)
		#expect(IRCDiagnosticStrings.malformedMessage(numeric: UInt.max, sequence: "x").isEmpty == false)
	}
}
