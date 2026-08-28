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

@testable import Glasstual
import Testing

@MainActor
struct IRCISupportPrefixTests {
	private func supportInfo(_ configuration: String) -> IRCISupportInfo {
		let client = GLTTestClient()
		let supportInfo = IRCISupportInfo(client: client)

		supportInfo.processConfigurationData(configuration)

		return supportInfo
	}

	/// `(ab)👍` has matching UTF-16 lengths but produces two mode symbols
	/// against a single prefix character, which used to trap on lookup.
	@Test
	func prefixTokenWithUnequalCharacterCountsIsRejected() {
		#expect(ISupportTokenParser.userPrefixConfiguration(from: "(ab)👍") == nil)
		#expect(ISupportTokenParser.userPrefixConfiguration(from: "(ov)@") == nil)
	}

	@Test
	func wellFormedPrefixTokenIsAccepted() throws {
		let configuration = try #require(ISupportTokenParser.userPrefixConfiguration(from: "(qaohv)~&@%+"))

		#expect(configuration.modeSymbols == ["q", "a", "o", "h", "v"])
		#expect(configuration.characters == ["~", "&", "@", "%", "+"])
	}

	@Test
	func malformedPrefixTokenLeavesLookupsIntact() {
		let supportInfo = supportInfo("PREFIX=(ab)👍")

		#expect(supportInfo.userPrefix(forModeSymbol: "b") == nil)
		#expect(supportInfo.userPrefix(forModeSymbol: "o") == "@")
		#expect(supportInfo.modeSymbol(forUserPrefix: "👍") == nil)
	}

	@Test
	func prefixLookupsStayPairedForEveryMode() {
		let supportInfo = supportInfo("PREFIX=(qaohv)~&@%+")

		#expect(supportInfo.userPrefix(forModeSymbol: "v") == "+")
		#expect(supportInfo.modeSymbol(forUserPrefix: "~") == "q")
		#expect(supportInfo.userModeSymbols[IRCISupportUserModes.symbolsKey] == ["q", "a", "o", "h", "v"])
		#expect(supportInfo.userModeSymbols[IRCISupportUserModes.charactersKey] == ["~", "&", "@", "%", "+"])
	}

	/// More prefix modes than the rank ceiling used to underflow `UInt`.
	@Test
	func rankDoesNotUnderflowWithMoreModesThanTheRankCeiling() {
		let ascii = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
		let latin = (0xC0 ... 0xFF).compactMap { UnicodeScalar($0).map(Character.init) }
		let symbols = Array((ascii + latin).prefix(105))

		#expect(symbols.count == 105)

		let token = "(" + String(symbols) + ")" + String(symbols)
		let supportInfo = supportInfo("PREFIX=" + token)

		#expect(supportInfo.rankForUserPrefix(withMode: String(symbols[0])) == 100)
		#expect(supportInfo.rankForUserPrefix(withMode: String(symbols[99])) == 1)
		#expect(supportInfo.rankForUserPrefix(withMode: String(symbols[104])) == 1)
		#expect(supportInfo.rankForUserPrefix(withMode: "\u{FFFD}") == 0)
	}
}
