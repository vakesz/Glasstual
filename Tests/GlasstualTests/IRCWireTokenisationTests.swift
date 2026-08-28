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

@MainActor
struct IRCWireTokenisationTests {
	/// U+00A0 is whitespace to Foundation but a perfectly ordinary parameter
	/// character on the wire.
	@Test
	func nonBreakingSpaceIsNotASeparator() throws {
		let line = try #require(LineParser.parsedLine(fromLine: ":s!u@h PRIVMSG #a\u{00A0}b :hi"))

		#expect(line.command == "PRIVMSG")
		#expect(line.parameters == ["#a\u{00A0}b", "hi"])
	}

	/// A combining mark after a space used to fuse into one non-whitespace
	/// grapheme and suppress the split.
	@Test
	func aCombiningMarkAfterASpaceStillSplits() throws {
		let line = try #require(LineParser.parsedLine(fromLine: ":s!u@h PRIVMSG #a \u{0301}text"))

		#expect(line.parameters == ["#a", "\u{0301}text"])
	}

	@Test
	func runsOfSpacesAreCollapsed() throws {
		let line = try #require(LineParser.parsedLine(fromLine: ":s!u@h  PRIVMSG   #a   :hi there"))

		#expect(line.senderSection == "s!u@h")
		#expect(line.command == "PRIVMSG")
		#expect(line.parameters == ["#a", "hi there"])
	}

	@Test
	func wireTokensSplitOnSpaceOnly() {
		#expect(LineParser.wireTokens(in: "a b  c") == ["a", "b", "c"])
		#expect(LineParser.wireTokens(in: "a\u{00A0}b") == ["a\u{00A0}b"])
		#expect(LineParser.wireTokens(in: "a\tb") == ["a\tb"])
		#expect(LineParser.wireTokens(in: "   ").isEmpty)
	}

	@Test
	func isupportTokensDoNotSplitOnUnicodeWhitespace() {
		let supportInfo = IRCISupportInfo()

		supportInfo.processConfigurationData("NETWORK=Ex\u{00A0}ample")

		#expect(supportInfo.networkName == "Ex\u{00A0}ample")
	}

	@Test
	func capabilityNamesDoNotSplitOnUnicodeWhitespace() {
		let offered = CapabilityRegistry.parseCapabilityList("sasl multi-prefix")

		#expect(offered.keys.sorted() == ["multi-prefix", "sasl"])
		#expect(CapabilityRegistry.parseCapabilityList("a\u{00A0}b").keys.first == "a\u{00A0}b")
	}

	@Test
	func ctcpCommandsSplitOnSpaceOnly() throws {
		let parsed = try #require(IRCCTCPPolicy.commandAndArguments(from: "VERSION some args"))

		#expect(parsed.command == "VERSION")
		#expect(parsed.arguments == "some args")

		let fused = try #require(IRCCTCPPolicy.commandAndArguments(from: "PING\u{00A0}1"))

		#expect(fused.command == "PING\u{00A0}1")
		#expect(fused.arguments.isEmpty)
	}
}
