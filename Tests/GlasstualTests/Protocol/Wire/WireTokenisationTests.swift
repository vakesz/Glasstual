// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing

@MainActor
struct WireTokenisationTests {
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
		let supportInfo = ISupport()

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
		let parsed = try #require(CTCPPolicy.commandAndArguments(from: "VERSION some args"))

		#expect(parsed.rawCommand == "VERSION")
		#expect(parsed.arguments == "some args")

		let fused = try #require(CTCPPolicy.commandAndArguments(from: "PING\u{00A0}1"))

		#expect(fused.rawCommand == "PING\u{00A0}1")
		#expect(fused.verb == nil)
		#expect(fused.arguments.isEmpty)
	}
}
