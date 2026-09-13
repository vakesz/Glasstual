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
struct ClientWireUtilitiesTests {
	@Test("Mode changes are split into batches no larger than the server's limit")
	func modeChangesAreBatchedAtServerLimit() {
		#expect(
			ClientWireUtilities.compileModeChanges(
				symbol: "b",
				isSet: true,
				parameters: ["one", "", "two", "three", "four"],
				maximumModes: 3
			) == [
				ModeChangeGroup(symbols: "+bbb", parameters: ["one", "two", "three"]),
				ModeChangeGroup(symbols: "+b", parameters: ["four"]),
			]
		)

		#expect(
			ClientWireUtilities.compileModeChanges(
				symbol: "o",
				isSet: false,
				parameters: ["alice", "bob"],
				maximumModes: 4
			) == [ModeChangeGroup(symbols: "-oo", parameters: ["alice", "bob"])]
		)
	}

	/** The compiler used to hand back `"+bbb one two three"` and `sendModes`
	 split it again with the wire tokeniser — a round trip through text whose
	 only purpose was to be undone, and one a mask containing a space would not
	 have survived. The mode string and its parameters stay apart. */
	@Test("A parameter containing a space stays one parameter")
	func parametersWithSpacesSurviveCompilation() throws {
		let groups = ClientWireUtilities.compileModeChanges(
			symbol: "b",
			isSet: true,
			parameters: ["$r:real name", "*!*@example.org"],
			maximumModes: 0
		)
		let group = try #require(groups.first)

		#expect(groups.count == 1)
		#expect(group.parameters == ["$r:real name", "*!*@example.org"])
		#expect(group.wireArguments == ["+bb", "$r:real name", "*!*@example.org"])
	}

	/** A list sheet names its mode from ISUPPORT, and a server can withdraw the
	 token — with a `-` prefixed token, or by resetting the whole set on
	 reconnect — while the sheet is still open. There is no mode to change then,
	 which used to be a `precondition` rather than an answer. */
	@Test(
		"A symbol that is not one mode letter compiles to no changes",
		arguments: ["", "be", "  "]
	)
	func aSymbolThatIsNotOneModeLetterCompilesToNothing(_ symbol: String) {
		#expect(
			ClientWireUtilities.compileModeChanges(
				symbol: symbol,
				isSet: false,
				parameters: ["one", "two"],
				maximumModes: 3
			).isEmpty
		)
	}

	@Test("A credential sent to services is redacted without changing its spacing")
	func serviceCredentialsAreRedactedWithoutChangingSpacing() {
		#expect(
			WireRedaction.redactedServiceMessage("IDENTIFY hunter2", sentTo: "NickServ")
				== "IDENTIFY ••••••"
		)
		#expect(
			WireRedaction.redactedServiceMessage("SET PASSWORD old  new", sentTo: "Q@CServe.quakenet.org")
				== "SET PASSWORD ••••••  ••••••"
		)
		#expect(
			WireRedaction.redactedServiceMessage("SET EMAIL me@example.com", sentTo: "NickServ")
				== "SET EMAIL me@example.com"
		)
		#expect(
			WireRedaction.redactedServiceMessage("IDENTIFY hunter2", sentTo: "friend")
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

	/// The transport is what turns a chat-history request into a line, so a
	/// labelled one gets its tag through the same path as any other tagged
	/// command.
	@Test("A labelled chat history request carries its tag and its own arguments")
	func chatHistoryRequestsAreTaggedByTheTransport() {
		#expect(
			SendingMessage.string(
				command: ClientWireUtilities.chatHistoryCommand,
				arguments: ["BEFORE", "#swift", "timestamp=2026-08-26T12:00:00.000Z", "50"],
				tags: ["label": "history-1"]
			) == "@label=history-1 CHATHISTORY BEFORE #swift timestamp=2026-08-26T12:00:00.000Z 50"
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

@MainActor
struct IRCClientNicknameFormatPaddingTests {
	/// `scanInt()` yields Int.min for this format, and `abs(Int.min)` traps.
	@Test
	func extremeNegativePaddingDoesNotTrap() {
		let formatted = ClientWireUtilities.formatNickname(
			"nick",
			modeSymbol: "@",
			format: "%-9223372036854775808n"
		)

		#expect(formatted.hasSuffix("nick"))
	}

	@Test
	func ordinaryPaddingIsUnchanged() {
		#expect(
			ClientWireUtilities.formatNickname("ab", modeSymbol: "@", format: "<%-5n>") == "<   ab>"
		)
		#expect(
			ClientWireUtilities.formatNickname("ab", modeSymbol: "@", format: "<%5n>") == "<ab   >"
		)
	}
}
