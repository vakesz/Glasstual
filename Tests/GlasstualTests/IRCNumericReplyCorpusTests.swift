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

/// Behaviour corpus for numeric reply classification, the nickname retry
/// ladder, and the WHOX request/response token.
@MainActor
struct IRCNumericReplyCorpusTests {
	nonisolated struct NumericCase: Sendable { // nonisolated: value
		let numeric: UInt
		let isError: Bool

		init(_ numeric: UInt, isError: Bool) {
			self.numeric = numeric
			self.isError = isError
		}
	}

	/// Errors are the 401-596 band, with RPL_NOMOTD carved out because servers
	/// send it as an ordinary reply.
	nonisolated static let classificationCases: [NumericCase] = [ // nonisolated: let
		NumericCase(1, isError: false),
		NumericCase(5, isError: false),
		NumericCase(315, isError: false),
		NumericCase(353, isError: false),
		NumericCase(400, isError: false),
		NumericCase(401, isError: true),
		NumericCase(403, isError: true),
		NumericCase(421, isError: true),
		/* RPL_NOMOTD sits inside the error band but is not an error. */
		NumericCase(422, isError: false),
		NumericCase(433, isError: true),
		NumericCase(475, isError: true),
		NumericCase(524, isError: true),
		NumericCase(596, isError: true),
		/* The watch/away notification band above 596 is not an error. */
		NumericCase(597, isError: false),
		NumericCase(600, isError: false),
		NumericCase(734, isError: false),
		/* SASL failures are reported as replies, not as errors. */
		NumericCase(902, isError: false),
		NumericCase(904, isError: false),
		NumericCase(926, isError: false),
	]

	@Test(arguments: Self.classificationCases)
	func classifiesErrorNumerics(testCase: NumericCase) {
		#expect(IRCNumeric.isErrorReply(testCase.numeric) == testCase.isError)
	}

	/// Replies whose text the client rewrites are printed even when a plugin
	/// or filter would otherwise swallow them.
	@Test(arguments: [
		NumericCase(221, isError: false),
		NumericCase(324, isError: false),
		NumericCase(332, isError: false),
		NumericCase(333, isError: false),
	])
	func specialFilteringCoversModeAndTopicReplies(testCase: NumericCase) {
		#expect(IRCNumericReplyPolicy.requiresSpecialFiltering(testCase.numeric))
	}

	@Test(arguments: [1 as UInt, 5, 353, 366, 401, 422, 433, 900])
	func specialFilteringCoversNothingElse(numeric: UInt) {
		#expect(IRCNumericReplyPolicy.requiresSpecialFiltering(numeric) == false)
	}

	@Test
	func catalogNumericsMatchTheWireProtocol() {
		#expect(IRCNumeric.welcome.rawValue == 1)
		#expect(IRCNumeric.isupport.rawValue == 5)
		#expect(IRCNumeric.namereply.rawValue == 353)
		#expect(IRCNumeric.whospcrpl.rawValue == 354)
		#expect(IRCNumeric.nomotd.rawValue == 422)
		#expect(IRCNumeric.nicknameinuse.rawValue == 433)
		#expect(IRCNumeric.erroneusnickname.rawValue == 432)
		#expect(IRCNumeric.unavailresource.rawValue == 437)
	}

	// MARK: - Nickname retry ladder

	nonisolated struct AlternateCase: Sendable { // nonisolated: value
		let attempt: UInt
		let nicknames: [String]
		let chosen: String?

		init(_ attempt: UInt, _ nicknames: [String], _ chosen: String?) {
			self.attempt = attempt
			self.nicknames = nicknames
			self.chosen = chosen
		}
	}

	/// Configured alternates are used in order, once each.
	@Test(arguments: [
		AlternateCase(0, ["alt1", "alt2"], "alt1"),
		AlternateCase(1, ["alt1", "alt2"], "alt2"),
		AlternateCase(2, ["alt1", "alt2"], nil),
		AlternateCase(0, [], nil),
		AlternateCase(5, ["only"], nil),
	])
	func walksTheAlternateNicknameList(testCase: AlternateCase) {
		#expect(IRCNicknameRetryPolicy.alternate(at: testCase.attempt, from: testCase.nicknames) == testCase.chosen)
	}

	nonisolated struct PaddingCase: Sendable { // nonisolated: value
		let nickname: String?
		let maximumLength: UInt
		let padded: String

		init(_ nickname: String?, maximumLength: UInt, padded: String) {
			self.nickname = nickname
			self.maximumLength = maximumLength
			self.padded = padded
		}
	}

	/// Once the alternates run out the nickname grows an underscore, and once
	/// it hits the length limit the underscores eat the tail.
	@Test(arguments: [
		PaddingCase("nick", maximumLength: 31, padded: "nick_"),
		PaddingCase("nick", maximumLength: 5, padded: "nick_"),
		PaddingCase("abcde", maximumLength: 5, padded: "abcd_"),
		PaddingCase("abcd_", maximumLength: 5, padded: "abc__"),
		PaddingCase("abc__", maximumLength: 5, padded: "ab___"),
		/* Nothing left to pad: fall back to the always-legal nickname. */
		PaddingCase("_____", maximumLength: 5, padded: "0"),
		PaddingCase(nil, maximumLength: 31, padded: "0"),
	])
	func padsNicknamesTowardsTheLengthLimit(testCase: PaddingCase) {
		#expect(
			IRCNicknameRetryPolicy.padded(testCase.nickname, maximumLength: testCase.maximumLength)
				== testCase.padded
		)
	}

	@Test
	func retryPolicyDefaults() {
		#expect(IRCNicknameRetryPolicy.fallbackNickname == "0")
	}

	/** The retry padded to a hardcoded 31 whatever the server said, so on a
	 network with a shorter `NICKLEN` every retry drew another 432 until the
	 nickname was nothing but underscores. */
	@Test
	func aRetriedNicknameIsPaddedToTheAdvertisedNicknameLength() {
		let client = GLTTestClient(configDictionary: ["nickname": "abcdefghi", "username": "abcdefghi"])

		client.supportInfo.processConfigurationData("NICKLEN=9")
		client.isConnected = true
		client.tryingNicknameSentNickname = "abcdefghi"
		client.tryAnotherNickname()

		#expect(client.tryingNicknameSentNickname == "abcdefgh_")
	}

	/// Before ISUPPORT lands there is nothing to read, so the RFC-era default
	/// still stands in.
	@Test
	func aRetryBeforeISupportUsesTheDefaultLength() {
		let client = GLTTestClient(configDictionary: ["nickname": "nick", "username": "nick"])

		client.isConnected = true
		client.tryingNicknameSentNickname = "nick"
		client.tryAnotherNickname()

		#expect(client.tryingNicknameSentNickname == "nick_")
	}
}

/// The WHOX request token and the reply token that matches it.
@MainActor
struct IRCWHOXCorpusTests {
	private static func loggedInClient(supporting configuration: String?) -> GLTTestClient {
		CommandIndex.populateCommandIndex()

		let client = GLTTestClient(configDictionary: ["nickname": "me", "username": "me"])
		client.markAsLoggedIn()

		if let configuration {
			client.supportInfo.processConfigurationData(configuration)
		}

		return client
	}

	private static func sentLines(of client: GLTTestClient) -> [String] {
		(client.sentLines as NSArray).compactMap { $0 as? String }
	}

	@Test
	func requestsWhoxFieldsWhenTheServerAdvertisesIt() {
		let client = Self.loggedInClient(supporting: "WHOX")

		client.sendWho(toChannelNamed: "#chat")

		#expect(Self.sentLines(of: client) == ["WHO #chat %tcuhnfar,152"])
	}

	@Test
	func fallsBackToPlainWhoWithoutWhox() {
		let client = Self.loggedInClient(supporting: nil)

		client.sendWho(toChannelNamed: "#chat")

		#expect(Self.sentLines(of: client) == ["WHO #chat"])
	}

	@Test
	func sendsNothingBeforeLogin() {
		CommandIndex.populateCommandIndex()

		let client = GLTTestClient(configDictionary: ["nickname": "me", "username": "me"])

		client.sendWho(toChannelNamed: "#chat")

		#expect(Self.sentLines(of: client).isEmpty)
	}

	@Test
	func sendsNothingForAnEmptyChannelName() {
		let client = Self.loggedInClient(supporting: "WHOX")

		client.sendWho(toChannelNamed: "")

		#expect(Self.sentLines(of: client).isEmpty)
	}

	/// The token in the request is the token the reply handler matches on.
	@Test
	func requestTokenMatchesTheResponseToken() throws {
		let client = Self.loggedInClient(supporting: "WHOX")

		client.sendWho(toChannelNamed: "#chat")

		let request = try #require(Self.sentLines(of: client).first)
		let reply = try #require(
			Message(line: ":irc.example.org 354 me 152 ~user host alice H account :Real Name", on: client)
		)

		#expect(request.hasSuffix(",\(reply.param(at: 1))"))
		#expect(reply.commandNumeric == IRCNumeric.whospcrpl.rawValue)
	}
}
