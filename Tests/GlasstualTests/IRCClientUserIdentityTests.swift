/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
 * Copyright (c) 2010 - 2018 Codeux Software, LLC & respective contributors.
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

/// IRCv3 identity extensions, WHOX, and pre-away negotiation.
@MainActor
@Suite("IRC user identity")
struct IRCClientUserIdentityTests {
	@Test("ACCOUNT names, then unnames, a user we already know about")
	func accountNotifyUpdatesAccount() throws {
		let client = makeClient(named: "me")
		client.enableCapability(.accountNotify)
		let channel = try joinChannel("#chat", on: client)
		addUser(named: "alice", to: channel, on: client)

		try client.receiveAccountNotify(message(":alice!a@example.org ACCOUNT alice_acct", on: client))
		#expect(client.findUser("alice")?.account == "alice_acct")

		try client.receiveAccountNotify(message(":alice!a@example.org ACCOUNT *", on: client))
		#expect(client.findUser("alice")?.account == nil)

		try client.receiveAccountNotify(message(":stranger!s@example.org ACCOUNT acct", on: client))
		#expect(client.findUser("stranger") == nil)
	}

	@Test("An extended JOIN carries the account and the real name")
	func extendedJoinReadsAccountAndRealName() throws {
		let client = makeClient(named: "me")
		try joinChannel("#chat", on: client)
		client.enableCapability(.extendedJoin)

		try client.receiveJoin(message(
			":alice!a@example.org JOIN #chat alice_acct :Alice Liddell",
			on: client
		))

		#expect(client.findUser("alice")?.account == "alice_acct")
		#expect(client.findUser("alice")?.realName == "Alice Liddell")

		try client.receiveJoin(message(":bob!b@example.org JOIN #chat * :Bob", on: client))

		#expect(client.findUser("bob")?.account == nil)
		#expect(client.findUser("bob")?.realName == "Bob")
	}

	@Test("Without the capability, the extra JOIN parameters are not read as identity")
	func joinParametersAreIgnoredWithoutExtendedJoin() throws {
		let client = makeClient(named: "me")
		try joinChannel("#chat", on: client)

		try client.receiveJoin(message(
			":alice!a@example.org JOIN #chat alice_acct :Alice Liddell",
			on: client
		))

		let alice = client.findUser("alice")
		#expect(alice != nil)
		#expect(alice?.account == nil)
		#expect(alice?.realName == nil)
	}

	@Test("The account and bot tags on any message update the sender")
	func accountTagAndBotTagUpdateSender() throws {
		let client = makeClient(named: "me")
		let channel = try joinChannel("#chat", on: client)
		addUser(named: "alice", to: channel, on: client)

		try client.receivePrivmsgAndNotice(message(
			"@account=alice_acct :alice!a@example.org PRIVMSG #chat :hi",
			on: client
		))

		#expect(client.findUser("alice")?.account == "alice_acct")
		#expect(client.findUser("alice")?.isBot == false)

		try client.receivePrivmsgAndNotice(message(
			"@bot :alice!a@example.org NOTICE #chat :beep",
			on: client
		))

		#expect(client.findUser("alice")?.isBot == true)
		#expect(client.findUser("alice")?.account == "alice_acct")

		try client.receiveTagMessage(message(
			"@account=other;+typing=active :alice!a@example.org TAGMSG #chat",
			on: client
		))

		#expect(client.findUser("alice")?.account == "other")
	}

	@Test("SETNAME renames the user it came from")
	func setNameUpdatesRealName() throws {
		let client = makeClient(named: "me")
		client.enableCapability(.setName)
		let channel = try joinChannel("#chat", on: client)
		addUser(named: "alice", to: channel, on: client)

		try client.receiveSetName(message(":alice!a@example.org SETNAME :Alice P. Liddell", on: client))

		#expect(client.findUser("alice")?.realName == "Alice P. Liddell")
	}

	@Test("/setname is refused with an explanation until the server offers the capability")
	func setNameCommandRequiresCapability() {
		let client = makeClient(named: "me")
		client.markAsLoggedIn()

		client.sendCommand("SETNAME New Name", completeTarget: false, target: nil)

		#expect(client.sentLines.count == 0)
		#expect(client.printedLines.count == 1)

		client.enableCapability(.setName)
		client.sendCommand("SETNAME New Name", completeTarget: false, target: nil)

		#expect(sentLines(of: client) == ["SETNAME :New Name"])
	}

	@Test("An invite for somebody else is printed in the channel it names, and nowhere else")
	func inviteForSomebodyElseIsPrintedInChannel() throws {
		let client = makeClient(named: "me")
		let channel = try joinChannel("#chat", on: client)

		try client.receiveInvite(message(":alice!a@example.org INVITE bob #chat", on: client))

		#expect(client.printedLines.count == 1)
		let printed = try #require(printedLine(at: 0, on: client))
		#expect(printed["channel"] as? Channel === channel)
		#expect((printed["lineType"] as? NSNumber)?.uintValue == TVCLogLineType.invite.rawValue)

		let body = printed["messageBody"] as? String
		#expect(body?.contains("alice") == true)
		#expect(body?.contains("bob") == true)
		#expect(body?.contains("#chat") == true)

		try client.receiveInvite(message(":alice!a@example.org INVITE bob #other", on: client))
		#expect(client.printedLines.count == 1)
	}

	@Test("An invite for me is a prompt on the server console, not a channel line")
	func inviteForMyselfStillUsesInvitePrompt() throws {
		let client = makeClient(named: "me")

		try client.receiveInvite(message(":alice!a@example.org INVITE me #chat", on: client))

		#expect(client.printedLines.count == 1)
		let printed = try #require(printedLine(at: 0, on: client))
		#expect(printed["channel"] == nil)
		#expect((printed["messageBody"] as? String)?.contains("invited you") == true)
	}

	@Test("WHO asks for the WHOX fields only once the server has advertised WHOX")
	func whoUsesWhoxWhenSupported() {
		let client = makeClient(named: "me")
		client.markAsLoggedIn()

		client.sendWho(toChannelNamed: "#chat")
		#expect(sentLines(of: client).last == "WHO #chat")

		client.supportInfo.processConfigurationData("WHOX")
		client.sendWho(toChannelNamed: "#chat")

		#expect(sentLines(of: client).last == "WHO #chat %tcuhnfar,152")
	}

	@Test("A WHOX reply fills in the identity, the flags and the channel modes")
	func whoxReplyIsParsed() throws {
		let client = makeClient(named: "me")
		client.supportInfo.processConfigurationData("WHOX BOT=B PREFIX=(ov)@+")
		let channel = try joinChannel("#chat", on: client)

		try client.receiveNumericReply(message(
			":irc.example.net 354 me 152 #chat ~alice host.example.org alice H*@B alice_acct :Alice",
			on: client
		))

		let alice = client.findUser("alice")
		#expect(alice?.username == "~alice")
		#expect(alice?.address == "host.example.org")
		#expect(alice?.realName == "Alice")
		#expect(alice?.account == "alice_acct")
		#expect(alice?.isIRCop == true)
		#expect(alice?.isBot == true)
		#expect(alice?.isAway == false)
		#expect(channel.findMember("alice")?.modes == "o")

		try client.receiveNumericReply(message(
			":irc.example.net 354 me 152 #chat ~bob host.example.org bob G 0 :Bob",
			on: client
		))

		let bob = client.findUser("bob")
		#expect(bob != nil)
		#expect(bob?.account == nil)
		#expect(bob?.isIRCop == false)
		#expect(bob?.isBot == false)

		try client.receiveNumericReply(message(
			":irc.example.net 354 me 999 #chat ~eve host eve H 0 :Eve",
			on: client
		))
		#expect(client.findUser("eve") == nil)
	}

	@Test("A plain WHO reply updates the identity but leaves the account it did not carry")
	func whoReplyStillParsesWithoutWhox() throws {
		let client = makeClient(named: "me")
		client.supportInfo.processConfigurationData("PREFIX=(ov)@+")
		let channel = try joinChannel("#chat", on: client)
		let existing = addUser(named: "alice", to: channel, on: client)

		client.modify(existing) { mutableUser in
			mutableUser.account = "kept"
		}

		try client.receiveNumericReply(message(
			":irc.example.net 352 me #chat ~alice host.example.org irc.example.net alice H+ :0 Alice",
			on: client
		))

		let alice = client.findUser("alice")
		#expect(alice?.username == "~alice")
		#expect(alice?.realName == "Alice")
		#expect(alice?.account == "kept")
	}

	@Test("pre-away is requested when offered, and acknowledging it sends nothing yet")
	func preAwayIsRequestedAndRestoresAwayOnReconnect() throws {
		let client = makeClient(named: "me")

		try client.receiveCapabilityOrAuthenticationRequest(message(
			":irc.example.net CAP * LS :pre-away",
			on: client
		))
		#expect(capabilityCommands(of: client) == ["REQ pre-away"])

		try client.receiveCapabilityOrAuthenticationRequest(message(
			":irc.example.net CAP me ACK :pre-away",
			on: client
		))

		#expect(client.isCapabilityEnabled(.preAway))
		#expect(capabilityCommands(of: client).last == "END")
		#expect(client.sentLines.count == 0)
	}

	@Test("Reconnecting with pre-away restores the away message before CAP END")
	func preAwaySendsAwayBeforeCapEndWhenReconnecting() {
		let client = makeClient(named: "me")
		client.markAsLoggedIn()
		client.toggleAwayStatus(true, withComment: "brb")
		#expect(sentLines(of: client) == ["AWAY :brb"])

		client.sentLines.removeAllObjects()
		client.isLoggedIn = false
		client.connectType = .reconnect
		client.enableCapability(.preAway)
		client.sendNextQueuedCapability()

		#expect(sentLines(of: client) == ["AWAY :brb"])
		#expect(capabilityCommands(of: client) == ["END"])
	}

	@Test("Reconnecting without pre-away sends no early AWAY")
	func preAwayDoesNothingWithoutCapability() {
		let client = makeClient(named: "me")
		client.markAsLoggedIn()
		client.toggleAwayStatus(true, withComment: "brb")
		client.sentLines.removeAllObjects()
		client.isLoggedIn = false
		client.connectType = .reconnect
		client.sendNextQueuedCapability()

		#expect(client.sentLines.count == 0)
		#expect(capabilityCommands(of: client) == ["END"])
	}

	private func makeClient(named nickname: String) -> GLTTestClient {
		GLTTestClient(configDictionary: ["nickname": nickname, "username": nickname])
	}

	@discardableResult
	private func joinChannel(_ name: String, on client: GLTTestClient) throws -> Channel {
		let channel = try #require(client.findChannelOrCreate(name))
		channel.activate()

		return channel
	}

	@discardableResult
	private func addUser(named nickname: String, to channel: Channel, on client: GLTTestClient) -> User {
		let user = client.findUserOrCreate(nickname)
		channel.addMember(ChannelUser(user: user))

		return user
	}

	private func message(_ line: String, on client: IRCClient) throws -> Message {
		try #require(Message(line: line, on: client))
	}

	private func sentLines(of client: GLTTestClient) -> [String] {
		(client.sentLines as NSArray).compactMap { $0 as? String }
	}

	private func capabilityCommands(of client: GLTTestClient) -> [String] {
		(client.sentCapabilityCommands as NSArray).compactMap { $0 as? String }
	}

	private func printedLine(at index: Int, on client: GLTTestClient) -> [String: Any]? {
		client.printedLines[index] as? [String: Any]
	}
}
