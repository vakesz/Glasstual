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
import XCTest

final class IRCClientInboundHandlerPolicyTests: XCTestCase {
	func testPrivmsgAndNoticeClassification() {
		let plain = IRCInboundTextPolicy.classify(command: "PRIVMSG", payload: "hello")
		XCTAssertEqual(plain.text, "hello")
		XCTAssertEqual(plain.lineType, .privateMessage)

		let action = IRCInboundTextPolicy.classify(command: "PRIVMSG", payload: "\u{1}ACTION waves\u{1}")
		XCTAssertEqual(action.text, "waves")
		XCTAssertEqual(action.lineType, .action)

		let reply = IRCInboundTextPolicy.classify(command: "NOTICE", payload: "\u{1}PING 42\u{1}")
		XCTAssertEqual(reply.text, "PING 42")
		XCTAssertEqual(reply.lineType, .ctcpReply)
	}

	func testCTCPParsingAndLagRatings() {
		let parsed = IRCCTCPPolicy.commandAndArguments(from: "ping 123")
		XCTAssertEqual(parsed?.command, "PING")
		XCTAssertEqual(parsed?.arguments, "123")
		XCTAssertNil(IRCCTCPPolicy.commandAndArguments(from: ""))
		XCTAssertEqual(IRCCTCPLagRating(milliseconds: 10), .excellent)
		XCTAssertEqual(IRCCTCPLagRating(milliseconds: 301), .verySlow)
	}

	func testIdentityAndClientTagNormalization() {
		XCTAssertNil(IRCIdentityPolicy.account(fromWireValue: "*"))
		XCTAssertNil(IRCIdentityPolicy.account(fromWireValue: "0"))
		XCTAssertEqual(IRCIdentityPolicy.account(fromWireValue: "alice"), "alice")
		XCTAssertEqual(
			IRCIdentityPolicy.clientTags(from: ["+typing": "active", "msgid": "1"]),
			["typing": "active"]
		)
	}

	func testEventEligibilityPolicies() {
		XCTAssertTrue(IRCMembershipEventPolicy.shouldPrint(
			isLocalUser: true, showJoinLeave: false, channelIgnoresEvents: true, addressBookIgnoresEvents: true
		))
		XCTAssertFalse(IRCMembershipEventPolicy.shouldPrint(
			isLocalUser: false, showJoinLeave: true, channelIgnoresEvents: false, addressBookIgnoresEvents: true
		))
		XCTAssertTrue(IRCInboundEventPolicy.cancelsReconnect(
			forError: "Closing Link: user (Max SendQ exceeded)"
		))
		XCTAssertTrue(IRCInboundEventPolicy.acceptsCertificateChunk(String(repeating: "a", count: 65)))
		XCTAssertFalse(IRCInboundEventPolicy.acceptsCertificateChunk(String(repeating: "a", count: 66)))
	}

	func testChanServChannelNoticeRemovesDestinationPrefix() throws {
		let notice = try XCTUnwrap(IRCServiceNoticePolicy.channelNotice(from: "[#swift] Welcome back"))
		XCTAssertEqual(notice.channelName, "#swift")
		XCTAssertEqual(notice.text, "Welcome back")
		XCTAssertNil(IRCServiceNoticePolicy.channelNotice(from: "Welcome back"))
	}

	func testNickServIdentificationActionsMatchLegacyRoutes() {
		let dalNet = IRCServiceNoticePolicy.nickServAction(
			for: "This nickname is registered",
			context: .init(
				isWaiting: false,
				password: "secret",
				nickname: "alice",
				serverAddress: "irc.dal.net",
				sendsAuthenticationToUserServ: false,
				needsIdentificationTokens: ["nickname is registered"],
				successfulIdentificationTokens: []
			)
		)
		XCTAssertEqual(
			dalNet,
			.sendIdentification(target: "NickServ@services.dal.net", text: "IDENTIFY secret")
		)

		let userServ = IRCServiceNoticePolicy.nickServAction(
			for: "identify yourself",
			context: .init(
				isWaiting: false,
				password: "secret",
				nickname: "alice",
				serverAddress: "irc.example.net",
				sendsAuthenticationToUserServ: true,
				needsIdentificationTokens: ["identify yourself"],
				successfulIdentificationTokens: []
			)
		)
		XCTAssertEqual(userServ, .sendIdentification(target: "userserv", text: "login alice secret"))

		let success = IRCServiceNoticePolicy.nickServAction(
			for: "You are now identified",
			context: .init(
				isWaiting: true,
				password: nil,
				nickname: "alice",
				serverAddress: nil,
				sendsAuthenticationToUserServ: false,
				needsIdentificationTokens: [],
				successfulIdentificationTokens: ["now identified"]
			)
		)
		XCTAssertEqual(success, .identificationSucceeded)
	}
}
