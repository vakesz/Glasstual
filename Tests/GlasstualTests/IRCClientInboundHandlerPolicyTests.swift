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
@Suite("Inbound handler policy")
struct IRCClientInboundHandlerPolicyTests {
	@Test("A CTCP wrapper decides whether a PRIVMSG or NOTICE is text, an action or a reply")
	func privmsgAndNoticeClassification() {
		let plain = IRCInboundTextPolicy.classify(command: "PRIVMSG", payload: "hello")

		#expect(plain.text == "hello")
		#expect(plain.lineType == .privateMessage)

		let action = IRCInboundTextPolicy.classify(command: "PRIVMSG", payload: "\u{1}ACTION waves\u{1}")

		#expect(action.text == "waves")
		#expect(action.lineType == .action)

		let reply = IRCInboundTextPolicy.classify(command: "NOTICE", payload: "\u{1}PING 42\u{1}")

		#expect(reply.text == "PING 42")
		#expect(reply.lineType == .ctcpReply)
	}

	@Test("A CTCP command is upper-cased, an empty payload is rejected, and lag is rated")
	func ctcpParsingAndLagRatings() {
		let parsed = IRCCTCPPolicy.commandAndArguments(from: "ping 123")

		#expect(parsed?.command == "PING")
		#expect(parsed?.arguments == "123")
		#expect(IRCCTCPPolicy.commandAndArguments(from: "") == nil)
		#expect(IRCCTCPLagRating(milliseconds: 10) == .excellent)
		#expect(IRCCTCPLagRating(milliseconds: 301) == .verySlow)
	}

	@Test("A placeholder account is read as no account, and only client tags survive")
	func identityAndClientTagNormalization() {
		#expect(IRCIdentityPolicy.account(fromWireValue: "*") == nil)
		#expect(IRCIdentityPolicy.account(fromWireValue: "0") == nil)
		#expect(IRCIdentityPolicy.account(fromWireValue: "alice") == "alice")
		#expect(
			IRCIdentityPolicy.clientTags(from: ["+typing": "active", "msgid": "1"]) == ["typing": "active"]
		)
	}

	@Test("Membership, reconnect and certificate events keep their eligibility rules")
	func eventEligibilityPolicies() {
		#expect(IRCMembershipEventPolicy.shouldPrint(
			isLocalUser: true, showJoinLeave: false, channelIgnoresEvents: true, addressBookIgnoresEvents: true
		))
		#expect(IRCMembershipEventPolicy.shouldPrint(
			isLocalUser: false, showJoinLeave: true, channelIgnoresEvents: false, addressBookIgnoresEvents: true
		) == false)
		#expect(IRCInboundEventPolicy.cancelsReconnect(
			forError: "Closing Link: user (Max SendQ exceeded)"
		))
		#expect(IRCInboundEventPolicy.acceptsCertificateChunk(String(repeating: "a", count: 65)))
		#expect(IRCInboundEventPolicy.acceptsCertificateChunk(String(repeating: "a", count: 66)) == false)
	}

	@Test("A ChanServ notice addressed to a channel loses its destination prefix")
	func chanServChannelNoticeRemovesDestinationPrefix() throws {
		let notice = try #require(IRCServiceNoticePolicy.channelNotice(from: "[#swift] Welcome back"))

		#expect(notice.channelName == "#swift")
		#expect(notice.text == "Welcome back")
		#expect(IRCServiceNoticePolicy.channelNotice(from: "Welcome back") == nil)
	}

	@Test("NickServ notices route to the identification the network expects")
	func nickServIdentificationActionsMatchLegacyRoutes() {
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

		#expect(dalNet == .sendIdentification(target: "NickServ@services.dal.net", text: "IDENTIFY secret"))

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

		#expect(userServ == .sendIdentification(target: "userserv", text: "login alice secret"))

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

		#expect(success == .identificationSucceeded)
	}
}
