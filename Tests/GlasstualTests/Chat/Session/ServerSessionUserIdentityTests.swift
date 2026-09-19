// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2018 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing

/// IRCv3 identity extensions, WHOX, and pre-away negotiation.
@MainActor
@Suite("IRC user identity")
struct ServerSessionUserIdentityTests {
	@Test("ACCOUNT names, then unnames, a user we already know about")
	func accountNotifyUpdatesAccount() throws {
		let session = makeSession(named: "me")
		session.enableCapability(.accountNotify)
		let channel = try joinChannel("#chat", on: session)
		addUser(named: "alice", to: channel, on: session)

		try session.receiveAccountNotify(message(":alice!a@example.org ACCOUNT alice_acct", on: session))
		#expect(session.findUser("alice")?.account == "alice_acct")

		try session.receiveAccountNotify(message(":alice!a@example.org ACCOUNT *", on: session))
		#expect(session.findUser("alice")?.account == nil)

		try session.receiveAccountNotify(message(":stranger!s@example.org ACCOUNT acct", on: session))
		#expect(session.findUser("stranger") == nil)
	}

	@Test("An extended JOIN carries the account and the real name")
	func extendedJoinReadsAccountAndRealName() throws {
		let session = makeSession(named: "me")
		try joinChannel("#chat", on: session)
		session.enableCapability(.extendedJoin)

		try session.receiveJoin(message(
			":alice!a@example.org JOIN #chat alice_acct :Alice Liddell",
			on: session
		))

		#expect(session.findUser("alice")?.account == "alice_acct")
		#expect(session.findUser("alice")?.realName == "Alice Liddell")

		try session.receiveJoin(message(":bob!b@example.org JOIN #chat * :Bob", on: session))

		#expect(session.findUser("bob")?.account == nil)
		#expect(session.findUser("bob")?.realName == "Bob")
	}

	@Test("Without the capability, the extra JOIN parameters are not read as identity")
	func joinParametersAreIgnoredWithoutExtendedJoin() throws {
		let session = makeSession(named: "me")
		try joinChannel("#chat", on: session)

		try session.receiveJoin(message(
			":alice!a@example.org JOIN #chat alice_acct :Alice Liddell",
			on: session
		))

		let alice = session.findUser("alice")
		#expect(alice != nil)
		#expect(alice?.account == nil)
		#expect(alice?.realName == nil)
	}

	/// A tag is only the server's word once the server said it sends it: the
	/// `account-tag` capability, or the `BOT` token.
	@Test("Without account-tag or BOT, the account and bot tags are not read as identity")
	func identityTagsNeedNegotiation() throws {
		let session = makeSession(named: "me")
		let channel = try joinChannel("#chat", on: session)
		addUser(named: "alice", to: channel, on: session)

		try session.receivePrivmsgAndNotice(message(
			"@account=alice_acct;bot :alice!a@example.org PRIVMSG #chat :hi",
			on: session
		))

		#expect(session.findUser("alice")?.account == nil)
		#expect(session.findUser("alice")?.isBot == false)
	}

	@Test("The account and bot tags on any message update the sender")
	func accountTagAndBotTagUpdateSender() throws {
		let session = makeSession(named: "me")
		session.enableCapability(.accountTag)
		session.supportInfo.processConfigurationData("BOT=B")
		let channel = try joinChannel("#chat", on: session)
		addUser(named: "alice", to: channel, on: session)

		try session.receivePrivmsgAndNotice(message(
			"@account=alice_acct :alice!a@example.org PRIVMSG #chat :hi",
			on: session
		))

		#expect(session.findUser("alice")?.account == "alice_acct")
		#expect(session.findUser("alice")?.isBot == false)

		try session.receivePrivmsgAndNotice(message(
			"@bot :alice!a@example.org NOTICE #chat :beep",
			on: session
		))

		#expect(session.findUser("alice")?.isBot == true)
		#expect(session.findUser("alice")?.account == "alice_acct")

		try session.receiveTagMessage(message(
			"@account=other;+typing=active :alice!a@example.org TAGMSG #chat",
			on: session
		))

		#expect(session.findUser("alice")?.account == "other")
	}

	@Test("/setname is refused with an explanation until the server offers the capability")
	func setNameCommandRequiresCapability() {
		let session = makeSession(named: "me")
		session.markAsLoggedIn()

		session.sendCommand("SETNAME New Name", completeTarget: false, target: nil)

		#expect(session.sentLines.count == 0)
		#expect(session.printedLines.count == 1)

		session.enableCapability(.setName)
		session.sendCommand("SETNAME New Name", completeTarget: false, target: nil)

		#expect(sentLines(of: session) == ["SETNAME :New Name"])
	}

	@Test("An invite for somebody else is printed in the channel it names, and nowhere else")
	func inviteForSomebodyElseIsPrintedInChannel() throws {
		let session = makeSession(named: "me")
		let channel = try joinChannel("#chat", on: session)

		try session.receiveInvite(message(":alice!a@example.org INVITE bob #chat", on: session))

		#expect(session.printedLines.count == 1)
		let printed = try #require(printedLine(at: 0, on: session))
		#expect(printed["channel"] as? Conversation === channel)
		#expect((printed["lineType"] as? NSNumber)?.uintValue == ChatLineKind.invite.rawValue)

		let body = printed["messageBody"] as? String
		#expect(body?.contains("alice") == true)
		#expect(body?.contains("bob") == true)
		#expect(body?.contains("#chat") == true)

		try session.receiveInvite(message(":alice!a@example.org INVITE bob #other", on: session))
		#expect(session.printedLines.count == 1)
	}

	@Test("An invite for me is a prompt on the server console, not a channel line")
	func inviteForMyselfStillUsesInvitePrompt() throws {
		let session = makeSession(named: "me")

		try session.receiveInvite(message(":alice!a@example.org INVITE me #chat", on: session))

		#expect(session.printedLines.count == 1)
		let printed = try #require(printedLine(at: 0, on: session))
		#expect(printed["channel"] == nil)
		#expect((printed["messageBody"] as? String)?.contains("invited you") == true)
	}

	@Test("WHO asks for the WHOX fields only once the server has advertised WHOX")
	func whoUsesWhoxWhenSupported() {
		let session = makeSession(named: "me")
		session.markAsLoggedIn()

		session.sendWho(toChannelNamed: "#chat")
		#expect(sentLines(of: session).last == "WHO #chat")

		session.supportInfo.processConfigurationData("WHOX")
		session.sendWho(toChannelNamed: "#chat")

		#expect(sentLines(of: session).last == "WHO #chat %tcuhnfar,152")
	}

	@Test("A WHOX reply fills in the identity, the flags and the channel modes")
	func whoxReplyIsParsed() throws {
		let session = makeSession(named: "me")
		session.supportInfo.processConfigurationData("WHOX BOT=B PREFIX=(ov)@+")
		let channel = try joinChannel("#chat", on: session)

		try session.receiveNumericReply(message(
			":irc.example.net 354 me 152 #chat ~alice host.example.org alice H*@B alice_acct :Alice",
			on: session
		))

		let alice = session.findUser("alice")
		#expect(alice?.username == "~alice")
		#expect(alice?.address == "host.example.org")
		#expect(alice?.realName == "Alice")
		#expect(alice?.account == "alice_acct")
		#expect(alice?.isIRCop == true)
		#expect(alice?.isBot == true)
		#expect(alice?.isAway == false)
		#expect(channel.findMember("alice")?.modes == "o")

		try session.receiveNumericReply(message(
			":irc.example.net 354 me 152 #chat ~bob host.example.org bob G 0 :Bob",
			on: session
		))

		let bob = session.findUser("bob")
		#expect(bob != nil)
		#expect(bob?.account == nil)
		#expect(bob?.isIRCop == false)
		#expect(bob?.isBot == false)

		try session.receiveNumericReply(message(
			":irc.example.net 354 me 999 #chat ~eve host eve H 0 :Eve",
			on: session
		))
		#expect(session.findUser("eve") == nil)
	}

	@Test("A plain WHO reply updates the identity but leaves the account it did not carry")
	func whoReplyStillParsesWithoutWhox() throws {
		let session = makeSession(named: "me")
		session.supportInfo.processConfigurationData("PREFIX=(ov)@+")
		let channel = try joinChannel("#chat", on: session)
		let existing = addUser(named: "alice", to: channel, on: session)

		session.modify(existing) { mutableUser in
			mutableUser.account = "kept"
		}

		try session.receiveNumericReply(message(
			":irc.example.net 352 me #chat ~alice host.example.org irc.example.net alice H+ :0 Alice",
			on: session
		))

		let alice = session.findUser("alice")
		#expect(alice?.username == "~alice")
		#expect(alice?.realName == "Alice")
		#expect(alice?.account == "kept")
	}

	@Test("pre-away is requested when offered, and acknowledging it sends nothing yet")
	func preAwayIsRequestedAndRestoresAwayOnReconnect() throws {
		let session = makeSession(named: "me")

		try session.handleCapabilityOrAuthenticationRequest(message(
			":irc.example.net CAP * LS :pre-away",
			on: session
		))
		#expect(capabilityCommands(of: session) == ["REQ pre-away"])

		try session.handleCapabilityOrAuthenticationRequest(message(
			":irc.example.net CAP me ACK :pre-away",
			on: session
		))

		#expect(session.isCapabilityEnabled(.preAway))
		#expect(capabilityCommands(of: session).last == "END")
		#expect(session.sentLines.count == 0)
	}

	@Test("Reconnecting with pre-away restores the away message before CAP END")
	func preAwaySendsAwayBeforeCapEndWhenReconnecting() {
		let session = makeSession(named: "me")
		session.markAsLoggedIn()
		session.toggleAwayStatus(true, withComment: "brb")
		#expect(sentLines(of: session) == ["AWAY :brb"])

		session.sentLines.removeAllObjects()
		session.isLoggedIn = false
		session.connectType = .reconnect
		session.enableCapability(.preAway)
		session.advanceCapabilityNegotiation()

		#expect(sentLines(of: session) == ["AWAY :brb"])
		#expect(capabilityCommands(of: session) == ["END"])
	}

	@Test("Reconnecting without pre-away sends no early AWAY")
	func preAwayDoesNothingWithoutCapability() {
		let session = makeSession(named: "me")
		session.markAsLoggedIn()
		session.toggleAwayStatus(true, withComment: "brb")
		session.sentLines.removeAllObjects()
		session.isLoggedIn = false
		session.connectType = .reconnect
		session.advanceCapabilityNegotiation()

		#expect(session.sentLines.count == 0)
		#expect(capabilityCommands(of: session) == ["END"])
	}

	private func makeSession(named nickname: String) -> TestServerSession {
		TestServerSession(configDictionary: ["nickname": nickname, "username": nickname])
	}

	@discardableResult
	private func joinChannel(_ name: String, on session: TestServerSession) throws -> Conversation {
		let channel = try #require(session.findConversationOrCreate(name))
		channel.activate()

		return channel
	}

	@discardableResult
	private func addUser(named nickname: String, to channel: Conversation, on session: TestServerSession) -> User {
		let user = session.findUserOrCreate(nickname)
		channel.addMember(Member(user: user))

		return user
	}

	private func message(_ line: String, on session: ServerSession) throws -> Message {
		try #require(Message(line: line, on: session))
	}

	private func sentLines(of session: TestServerSession) -> [String] {
		(session.sentLines as NSArray).compactMap { $0 as? String }
	}

	private func capabilityCommands(of session: TestServerSession) -> [String] {
		(session.sentCapabilityCommands as NSArray).compactMap { $0 as? String }
	}

	private func printedLine(at index: Int, on session: TestServerSession) -> [String: Any]? {
		session.printedLines[index] as? [String: Any]
	}
}
