/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
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

/// One parsed mode change, in the shape the assertions read.
nonisolated struct IRCSpecParsedMode: Equatable, CustomStringConvertible { // nonisolated: value
	let symbol: String
	let isSet: Bool
	let parameter: String?

	var description: String {
		"\(isSet ? "+" : "-")\(symbol)\(parameter.map { "(\($0))" } ?? "")"
	}
}

/// Channel MODE parsing: RFC 2811 §4 for what the modes mean, and
/// modern.ircdocs.horse ("The MODE command") for how ISUPPORT `CHANMODES` and
/// `PREFIX` decide which of them consume a parameter.
@Suite("Channel MODE parsing")
@MainActor
struct IRCSpecModeTests {
	/// A server advertising the common Libera/InspIRCd shape.
	private func supportInfo() -> IRCISupportInfo {
		let info = IRCISupportInfo()

		info.processConfigurationData("CHANMODES=beIq,k,fl,imnpstz PREFIX=(ohv)@%+")

		return info
	}

	private func parse(_ modeString: String) -> [IRCSpecParsedMode] {
		supportInfo().parseModes(modeString).map {
			IRCSpecParsedMode(symbol: $0.modeSymbol, isSet: $0.modeIsSet, parameter: $0.modeParameter)
		}
	}

	/// modern.ircdocs.horse: group A and group B modes take a parameter in
	/// both directions; group C only when being set; group D never.
	@Test("Parameters are consumed per CHANMODES group")
	func parametersFollowTheChanModesGroup() {
		#expect(parse("+b *!*@example.org") == [
			IRCSpecParsedMode(symbol: "b", isSet: true, parameter: "*!*@example.org"),
		])
		#expect(parse("-b *!*@example.org") == [
			IRCSpecParsedMode(symbol: "b", isSet: false, parameter: "*!*@example.org"),
		])
		#expect(parse("+k secret") == [
			IRCSpecParsedMode(symbol: "k", isSet: true, parameter: "secret"),
		])
		#expect(parse("-k secret") == [
			IRCSpecParsedMode(symbol: "k", isSet: false, parameter: "secret"),
		])
		#expect(parse("+l 50") == [
			IRCSpecParsedMode(symbol: "l", isSet: true, parameter: "50"),
		])
		#expect(parse("-l") == [
			IRCSpecParsedMode(symbol: "l", isSet: false, parameter: nil),
		])
		#expect(parse("+nt") == [
			IRCSpecParsedMode(symbol: "n", isSet: true, parameter: nil),
			IRCSpecParsedMode(symbol: "t", isSet: true, parameter: nil),
		])
	}

	/// RFC 2811 §4.1: a prefix mode names the member it applies to, so it
	/// always consumes one parameter.
	@Test("A PREFIX mode always consumes a nickname")
	func prefixModesConsumeANickname() {
		#expect(parse("+o alice") == [
			IRCSpecParsedMode(symbol: "o", isSet: true, parameter: "alice"),
		])
		#expect(parse("-o alice") == [
			IRCSpecParsedMode(symbol: "o", isSet: false, parameter: "alice"),
		])
		#expect(parse("+ovh alice bob carol") == [
			IRCSpecParsedMode(symbol: "o", isSet: true, parameter: "alice"),
			IRCSpecParsedMode(symbol: "v", isSet: true, parameter: "bob"),
			IRCSpecParsedMode(symbol: "h", isSet: true, parameter: "carol"),
		])
	}

	/// Parameters are consumed in the order the mode letters appear, across a
	/// run of mixed types. Getting this wrong hands one member another's
	/// privileges.
	@Test("Parameters are consumed in mode order across mixed types")
	func parametersAreConsumedInOrder() {
		#expect(parse("+okl alice secret 50") == [
			IRCSpecParsedMode(symbol: "o", isSet: true, parameter: "alice"),
			IRCSpecParsedMode(symbol: "k", isSet: true, parameter: "secret"),
			IRCSpecParsedMode(symbol: "l", isSet: true, parameter: "50"),
		])
		#expect(parse("+ntl 50") == [
			IRCSpecParsedMode(symbol: "n", isSet: true, parameter: nil),
			IRCSpecParsedMode(symbol: "t", isSet: true, parameter: nil),
			IRCSpecParsedMode(symbol: "l", isSet: true, parameter: "50"),
		])
	}

	/// A `+`/`-` inside the mode string flips the direction for everything
	/// after it, and each half keeps its own parameter rule.
	@Test("A +/- run flips direction mid-string")
	func directionRunsFlipMidString() {
		#expect(parse("+o-v alice bob") == [
			IRCSpecParsedMode(symbol: "o", isSet: true, parameter: "alice"),
			IRCSpecParsedMode(symbol: "v", isSet: false, parameter: "bob"),
		])
		#expect(parse("-l+k secret") == [
			IRCSpecParsedMode(symbol: "l", isSet: false, parameter: nil),
			IRCSpecParsedMode(symbol: "k", isSet: true, parameter: "secret"),
		])
		#expect(parse("+im-t") == [
			IRCSpecParsedMode(symbol: "i", isSet: true, parameter: nil),
			IRCSpecParsedMode(symbol: "m", isSet: true, parameter: nil),
			IRCSpecParsedMode(symbol: "t", isSet: false, parameter: nil),
		])
	}

	/// A mode the server never classified is assumed to take no parameter. The
	/// alternative — guessing that it does — would eat the next token and
	/// desynchronise every mode after it.
	@Test("An unknown mode takes no parameter and does not desynchronise the rest")
	func unknownModesDoNotConsumeParameters() {
		#expect(parse("+Zo alice") == [
			IRCSpecParsedMode(symbol: "Z", isSet: true, parameter: nil),
			IRCSpecParsedMode(symbol: "o", isSet: true, parameter: "alice"),
		])
	}

	/// A mode that wants a parameter but has none left is still the mode: a
	/// bare `MODE #chan +b` is how a client asks for the ban list.
	@Test("A parameterised mode with no parameter left is still parsed")
	func missingParametersAreTolerated() {
		#expect(parse("+b") == [
			IRCSpecParsedMode(symbol: "b", isSet: true, parameter: nil),
		])
		#expect(parse("+ovo alice") == [
			IRCSpecParsedMode(symbol: "o", isSet: true, parameter: "alice"),
			IRCSpecParsedMode(symbol: "v", isSet: true, parameter: nil),
			IRCSpecParsedMode(symbol: "o", isSet: true, parameter: nil),
		])
	}

	/// A mode string that never opens with `+` or `-` says nothing. Tokens
	/// before the first sign are skipped rather than read as mode letters.
	@Test("A mode string with no leading sign contributes nothing")
	func modeStringsNeedASign() {
		#expect(parse("ov alice bob").isEmpty)
		#expect(parse("").isEmpty)
	}

	/// The parser reads a whole `MODE` parameter list, so extra spaces between
	/// tokens — which RFC 1459 §2.3 allows — must not shift the parameters.
	@Test("RFC 1459 §2.3: runs of spaces between mode tokens are tolerated")
	func runsOfSpacesAreTolerated() {
		#expect(parse("+oo   alice   bob") == [
			IRCSpecParsedMode(symbol: "o", isSet: true, parameter: "alice"),
			IRCSpecParsedMode(symbol: "o", isSet: true, parameter: "bob"),
		])
	}

	/// A `MODE` reply arrives as `#channel <modes> <params...>`, and the
	/// handler passes everything from the mode string onward. Reassembling it
	/// from the parsed message has to give the same answer as parsing the
	/// tokens directly.
	@Test("A MODE line from the wire parses into the same changes")
	func wireLinesParseIntoTheSameChanges() throws {
		let client = GLTTestClient()
		let message = try #require(
			Message(line: ":op!u@h MODE #chan +oo-v alice bob carol", on: client)
		)

		#expect(message.params.first == "#chan")

		let changes = supportInfo().parseModes(message.sequence(1)).map {
			IRCSpecParsedMode(symbol: $0.modeSymbol, isSet: $0.modeIsSet, parameter: $0.modeParameter)
		}

		#expect(changes == [
			IRCSpecParsedMode(symbol: "o", isSet: true, parameter: "alice"),
			IRCSpecParsedMode(symbol: "o", isSet: true, parameter: "bob"),
			IRCSpecParsedMode(symbol: "v", isSet: false, parameter: "carol"),
		])
	}

	/// A server that squeezes the whole mode change into the trailing
	/// parameter — `MODE #chan :+i` — is still one mode change.
	@Test("A trailing-parameter MODE is the same as a middle-parameter one")
	func trailingParameterModesParseTheSame() throws {
		let client = GLTTestClient()
		let message = try #require(Message(line: ":op MODE #chan :+i", on: client))

		#expect(message.params == ["#chan", "+i"])
		#expect(parse(message.sequence(1)) == [
			IRCSpecParsedMode(symbol: "i", isSet: true, parameter: nil),
		])
	}

	/// A member's rank comes from `PREFIX` order, not from the mode letter, so
	/// a channel-mode change and a prefix change agree about who outranks whom.
	@Test("Prefix modes rank members in PREFIX order")
	func prefixModesRankMembers() {
		let info = supportInfo()

		#expect(info.rankForUserPrefix(withMode: "o") > info.rankForUserPrefix(withMode: "h"))
		#expect(info.rankForUserPrefix(withMode: "h") > info.rankForUserPrefix(withMode: "v"))
		#expect(info.userPrefix(forModeSymbol: "h") == "%")
	}
}
