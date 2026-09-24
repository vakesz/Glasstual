// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing

/// Behaviour corpus for numeric reply classification, the nickname retry
/// ladder, and the WHOX request/response token.
@MainActor
struct ServerNumericReplyCorpusTests {
	nonisolated struct NumericCase: Sendable {
		let numeric: UInt
		let isError: Bool

		init(_ numeric: UInt, isError: Bool) {
			self.numeric = numeric
			self.isError = isError
		}
	}

	/// Errors are the 400-596 band, with RPL_NOMOTD carved out because servers
	/// send it as an ordinary reply.
	nonisolated static let classificationCases: [NumericCase] = [
		NumericCase(1, isError: false),
		NumericCase(5, isError: false),
		NumericCase(315, isError: false),
		NumericCase(353, isError: false),
		NumericCase(400, isError: true),
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
		#expect(ServerNumeric.isErrorReply(testCase.numeric) == testCase.isError)
	}

	/// Replies whose text the session rewrites are printed even when a rule
	/// or filter would otherwise swallow them.
	@Test(arguments: [ServerNumeric.umodeis, .channelmodeis, .topic, .topicwhotime])
	func specialFilteringCoversModeAndTopicReplies(numeric: ServerNumeric) {
		#expect(numeric.requiresSpecialFiltering)
	}

	@Test(arguments: [ServerNumeric.welcome, .isupport, .namereply, .endofnames, .nosuchnick, .nomotd,
	                  .nicknameinuse, .loggedin])
	func specialFilteringCoversNothingElse(numeric: ServerNumeric) {
		#expect(numeric.requiresSpecialFiltering == false)
	}

	/// Every numeric a handler answers names its group, and the routing switch
	/// in `receiveNumericReply` is what turns that into the call.
	@Test
	func groupedNumericsAreRoutedToExactlyOneHandler() {
		#expect(ServerNumeric.welcome.group == .connection)
		#expect(ServerNumeric.whoisuser.group == .whois)
		#expect(ServerNumeric.namereply.group == .channel)
		#expect(ServerNumeric.mononline.group == .presence)
		#expect(ServerNumeric.saslsuccess.group == .authentication)

		/* A numeric no handler claims takes the generic reply path. */
		#expect(ServerNumeric.whoiscertfp.group == nil)
		#expect(ServerNumeric.clearwatch.group == nil)
	}

	/// The cases are declared in numeric order, which is how a reader finds one.
	@Test
	func catalogIsInNumericOrder() {
		let rawValues = ServerNumeric.allCases.map(\.rawValue)

		#expect(rawValues == rawValues.sorted())
		#expect(Set(rawValues).count == rawValues.count)
	}

	@Test
	func catalogNumericsMatchTheWireProtocol() {
		#expect(ServerNumeric.welcome.rawValue == 1)
		#expect(ServerNumeric.isupport.rawValue == 5)
		#expect(ServerNumeric.namereply.rawValue == 353)
		#expect(ServerNumeric.whospcrpl.rawValue == 354)
		#expect(ServerNumeric.nomotd.rawValue == 422)
		#expect(ServerNumeric.nicknameinuse.rawValue == 433)
		#expect(ServerNumeric.erroneusnickname.rawValue == 432)
		#expect(ServerNumeric.unavailresource.rawValue == 437)
	}

	// MARK: - Nickname retry ladder

	nonisolated struct AlternateCase: Sendable {
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
		#expect(NicknameRetryPolicy.alternate(at: testCase.attempt, from: testCase.nicknames) == testCase.chosen)
	}

	nonisolated struct PaddingCase: Sendable {
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
			NicknameRetryPolicy.padded(testCase.nickname, maximumLength: testCase.maximumLength)
				== testCase.padded
		)
	}

	/** The retry padded to a hardcoded 31 whatever the server said, so on a
	 network with a shorter `NICKLEN` every retry drew another 432 until the
	 nickname was nothing but underscores. */
	@Test
	func aRetriedNicknameIsPaddedToTheAdvertisedNicknameLength() {
		let session = TestServerSession(configDictionary: ["nickname": "abcdefghi", "username": "abcdefghi"])

		session.supportInfo.processConfigurationData("NICKLEN=9")
		session.setConnectionTransportForTesting(.connected)
		session.nicknameRetry.sentNickname = "abcdefghi"
		session.tryAnotherNickname()

		#expect(session.nicknameRetry.sentNickname == "abcdefgh_")
	}

	/// Before ISUPPORT lands there is nothing to read, so the RFC-era default
	/// still stands in.
	@Test
	func aRetryBeforeISupportUsesTheDefaultLength() {
		let session = TestServerSession(configDictionary: ["nickname": "nick", "username": "nick"])

		session.setConnectionTransportForTesting(.connected)
		session.nicknameRetry.sentNickname = "nick"
		session.tryAnotherNickname()

		#expect(session.nicknameRetry.sentNickname == "nick_")
	}
}

/// The WHOX request token and the reply token that matches it.
@MainActor
struct WHOXCorpusTests {
	private static func loggedInSession(supporting configuration: String?) -> TestServerSession {
		let session = TestServerSession(configDictionary: ["nickname": "me", "username": "me"])
		session.markAsLoggedIn()

		if let configuration {
			session.supportInfo.processConfigurationData(configuration)
		}

		return session
	}

	private static func sentLines(of session: TestServerSession) -> [String] {
		(session.sentLines as NSArray).compactMap { $0 as? String }
	}

	@Test
	func requestsWhoxFieldsWhenTheServerAdvertisesIt() {
		let session = Self.loggedInSession(supporting: "WHOX")

		session.sendWho(toChannelNamed: "#chat")

		#expect(Self.sentLines(of: session) == ["WHO #chat %tcuhnfar,152"])
	}

	@Test
	func fallsBackToPlainWhoWithoutWhox() {
		let session = Self.loggedInSession(supporting: nil)

		session.sendWho(toChannelNamed: "#chat")

		#expect(Self.sentLines(of: session) == ["WHO #chat"])
	}

	@Test
	func sendsNothingBeforeLogin() {
		let session = TestServerSession(configDictionary: ["nickname": "me", "username": "me"])

		session.sendWho(toChannelNamed: "#chat")

		#expect(Self.sentLines(of: session).isEmpty)
	}

	@Test
	func sendsNothingForAnEmptyChannelName() {
		let session = Self.loggedInSession(supporting: "WHOX")

		session.sendWho(toChannelNamed: "")

		#expect(Self.sentLines(of: session).isEmpty)
	}

	/// The token in the request is the token the reply handler matches on.
	@Test
	func requestTokenMatchesTheResponseToken() throws {
		let session = Self.loggedInSession(supporting: "WHOX")

		session.sendWho(toChannelNamed: "#chat")

		let request = try #require(Self.sentLines(of: session).first)
		let reply = try #require(
			Message(line: ":irc.example.org 354 me 152 ~user host alice H account :Real Name", on: session)
		)

		#expect(request.hasSuffix(",\(reply.param(at: 1))"))
		#expect(reply.commandNumeric == ServerNumeric.whospcrpl.rawValue)
	}
}
