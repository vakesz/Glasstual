// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

@testable import Glasstual
import Testing

@MainActor
@Suite("Inbound handler policy")
struct ClientInboundHandlerPolicyTests {
	@Test("A CTCP wrapper decides whether a PRIVMSG or NOTICE is text, an action or a reply")
	func privmsgAndNoticeClassification() {
		let plain = InboundTextPolicy.classify(command: "PRIVMSG", payload: "hello")

		#expect(plain.text == "hello")
		#expect(plain.lineType == .privateMessage)

		let action = InboundTextPolicy.classify(command: "PRIVMSG", payload: "\u{1}ACTION waves\u{1}")

		#expect(action.text == "waves")
		#expect(action.lineType == .action)

		let reply = InboundTextPolicy.classify(command: "NOTICE", payload: "\u{1}PING 42\u{1}")

		#expect(reply.text == "PING 42")
		#expect(reply.lineType == .ctcpReply)
	}

	@Test("A CTCP command is upper-cased, an empty payload is rejected, and lag is rated")
	func ctcpParsingAndLagRatings() {
		let parsed = CTCPPolicy.commandAndArguments(from: "ping 123")

		#expect(parsed?.command == "PING")
		#expect(parsed?.arguments == "123")
		#expect(CTCPPolicy.commandAndArguments(from: "") == nil)
		#expect(CTCPLagRating(milliseconds: 10) == .excellent)
		#expect(CTCPLagRating(milliseconds: 301) == .verySlow)
	}

	@Test("A placeholder account is read as no account, and only client tags survive")
	func identityAndClientTagNormalization() {
		#expect(IdentityPolicy.account(fromWireValue: "*") == nil)
		#expect(IdentityPolicy.account(fromWireValue: "0") == nil)
		#expect(IdentityPolicy.account(fromWireValue: "alice") == "alice")
		#expect(
			IdentityPolicy.clientTags(from: ["+typing": "active", "msgid": "1"]) == ["typing": "active"]
		)
	}

	@Test("Membership, reconnect and certificate events keep their eligibility rules")
	func eventEligibilityPolicies() {
		#expect(MembershipEventPolicy.shouldPrint(
			isLocalUser: true, showJoinLeave: false, channelIgnoresEvents: true, addressBookIgnoresEvents: true
		))
		#expect(MembershipEventPolicy.shouldPrint(
			isLocalUser: false, showJoinLeave: true, channelIgnoresEvents: false, addressBookIgnoresEvents: true
		) == false)
		#expect(InboundEventPolicy.cancelsReconnect(
			forError: "Closing Link: user (Max SendQ exceeded)"
		))
		#expect(InboundEventPolicy.acceptsCertificateChunk(String(repeating: "a", count: 65)))
		#expect(InboundEventPolicy.acceptsCertificateChunk(String(repeating: "a", count: 66)) == false)
	}

	@Test("A ChanServ notice addressed to a channel loses its destination prefix")
	func chanServChannelNoticeRemovesDestinationPrefix() throws {
		let notice = try #require(ServiceNoticePolicy.channelNotice(from: "[#swift] Welcome back"))

		#expect(notice.channelName == "#swift")
		#expect(notice.text == "Welcome back")
		#expect(ServiceNoticePolicy.channelNotice(from: "Welcome back") == nil)
	}

	@Test("NickServ notices route to the identification the network expects")
	func nickServIdentificationActionsMatchLegacyRoutes() {
		let dalNet = ServiceNoticePolicy.nickServAction(
			for: "This nickname is registered",
			context: .init(
				isWaiting: false,
				isIdentifiedWithSASL: false,
				permitsCredentialsInClear: true,
				password: "secret",
				nickname: "alice",
				serverAddress: "irc.dal.net",
				sendsAuthenticationToUserServ: false,
				needsIdentificationTokens: ["nickname is registered"],
				successfulIdentificationTokens: []
			)
		)

		#expect(dalNet == .sendIdentification(target: "NickServ@services.dal.net", text: "IDENTIFY secret"))

		let userServ = ServiceNoticePolicy.nickServAction(
			for: "identify yourself",
			context: .init(
				isWaiting: false,
				isIdentifiedWithSASL: false,
				permitsCredentialsInClear: true,
				password: "secret",
				nickname: "alice",
				serverAddress: "irc.example.net",
				sendsAuthenticationToUserServ: true,
				needsIdentificationTokens: ["identify yourself"],
				successfulIdentificationTokens: []
			)
		)

		#expect(userServ == .sendIdentification(target: "userserv", text: "login alice secret"))

		let success = ServiceNoticePolicy.nickServAction(
			for: "You are now identified",
			context: .init(
				isWaiting: true,
				isIdentifiedWithSASL: false,
				permitsCredentialsInClear: true,
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
