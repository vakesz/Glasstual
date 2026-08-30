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

@testable import Glasstual
import Testing

@MainActor
@Suite("Client wire utilities")
struct IRCClientWireUtilitiesTests {
	@Test("Mode changes are split into batches no larger than the server's limit")
	func modeChangesAreBatchedAtServerLimit() {
		#expect(
			ClientWireUtilities.compileModeChanges(
				symbol: "b",
				isSet: true,
				parameters: ["one", "", "two", "three", "four"],
				maximumModes: 3
			) == ["+bbb one two three", "+b four"]
		)

		#expect(
			ClientWireUtilities.compileModeChanges(
				symbol: "o",
				isSet: false,
				parameters: ["alice", "bob"],
				maximumModes: 4
			) == ["-oo alice bob"]
		)
	}

	@Test("A credential sent to services is redacted without changing its spacing")
	func serviceCredentialsAreRedactedWithoutChangingSpacing() {
		#expect(
			ClientWireUtilities.redactedServiceMessage("IDENTIFY hunter2", sentTo: "NickServ")
				== "IDENTIFY ••••••"
		)
		#expect(
			ClientWireUtilities.redactedServiceMessage("SET PASSWORD old  new", sentTo: "Q@CServe.quakenet.org")
				== "SET PASSWORD ••••••  ••••••"
		)
		#expect(
			ClientWireUtilities.redactedServiceMessage("SET EMAIL me@example.com", sentTo: "NickServ")
				== "SET EMAIL me@example.com"
		)
		#expect(
			ClientWireUtilities.redactedServiceMessage("IDENTIFY hunter2", sentTo: "friend")
				== "IDENTIFY hunter2"
		)
	}

	@Test("Nickname formatting keeps the mode marker and pads in UTF-16 units")
	func nicknameFormattingPreservesMarkersAndUTF16Padding() {
		#expect(
			ClientWireUtilities.formatNickname("alice", modeSymbol: "@", format: "[%@%8n] %%")
				== "[@alice   ] %"
		)
		#expect(
			ClientWireUtilities.formatNickname("🦊", modeSymbol: "", format: "%3n") == "🦊 "
		)
		#expect(
			ClientWireUtilities.formatNickname("bob", modeSymbol: "+", format: "%-5n%@") == "  bob+"
		)
	}

	@Test("A DCC address round trips as an IPv4 integer and passes IPv6 through")
	func dccWireRepresentationsRoundTripIPv4AndPreserveIPv6() {
		#expect(ClientWireUtilities.wireDCCAddress("192.168.1.10") == "3232235786")
		#expect(ClientWireUtilities.displayDCCAddress("3232235786") == "192.168.1.10")
		#expect(ClientWireUtilities.wireDCCAddress("2001:db8::1") == "2001:db8::1")
		#expect(ClientWireUtilities.displayDCCAddress("2001:db8::1") == "2001:db8::1")
		#expect(ClientWireUtilities.wireDCCAddress("not-an-address") == nil)
	}

	@Test("A DCC filename is quoted and escaped to match the wire grammar")
	func dccFilenameEscapingMatchesWireGrammar() {
		#expect(ClientWireUtilities.escapedDCCFilename("report.txt") == "report.txt")
		#expect(ClientWireUtilities.escapedDCCFilename("a/b file.txt") == "\"a_b file.txt\"")
		#expect(ClientWireUtilities.escapedDCCFilename("say \"hi\".txt") == "\"say \\\"hi\\\".txt\"")
	}

	@Test("Chat history commands name their selector and limit explicitly")
	func chatHistoryCommandsUseExplicitSelectorAndLimit() {
		#expect(
			ClientWireUtilities.chatHistoryLatestCommand(target: "#swift", selector: "*", limit: 100)
				== "CHATHISTORY LATEST #swift * 100"
		)
		#expect(
			ClientWireUtilities.chatHistoryBeforeCommand(
				target: "#swift",
				selector: "timestamp=2026-08-26T12:00:00.000Z",
				limit: 50
			) == "CHATHISTORY BEFORE #swift timestamp=2026-08-26T12:00:00.000Z 50"
		)
	}

	@Test("A netsplit nickname list under the limit keeps its order")
	func shortNetsplitNicknameListsRetainOrder() {
		#expect(
			ClientWireUtilities.netsplitNicknameList(["alice", "bob", "carol"], limit: 10)
				== "alice, bob, carol"
		)
	}
}
