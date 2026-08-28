/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \\ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\\__|\__,_|\__,_|_|
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

@testable import Glasstual
import XCTest

/// IRCv3 identity extensions, WHOX, and pre-away negotiation.
@MainActor
final class IRCClientUserIdentityTests: XCTestCase {
	func testAccountNotifyUpdatesAccount() {
		let client = makeClient(named: "me")
		let channel = joinChannel("#chat", on: client)
		addUser(named: "alice", to: channel, on: client)

		client.receiveAccountNotify(message(":alice!a@example.org ACCOUNT alice_acct", on: client))
		XCTAssertEqual(client.findUser("alice")?.account, "alice_acct")

		client.receiveAccountNotify(message(":alice!a@example.org ACCOUNT *", on: client))
		XCTAssertNil(client.findUser("alice")?.account)

		client.receiveAccountNotify(message(":stranger!s@example.org ACCOUNT acct", on: client))
		XCTAssertNil(client.findUser("stranger"))
	}

	func testExtendedJoinReadsAccountAndRealName() {
		let client = makeClient(named: "me")
		joinChannel("#chat", on: client)
		client.enableCapability(.extendedJoin)

		client.receiveJoin(message(
			":alice!a@example.org JOIN #chat alice_acct :Alice Liddell",
			on: client
		))

		XCTAssertEqual(client.findUser("alice")?.account, "alice_acct")
		XCTAssertEqual(client.findUser("alice")?.realName, "Alice Liddell")

		client.receiveJoin(message(":bob!b@example.org JOIN #chat * :Bob", on: client))

		XCTAssertNil(client.findUser("bob")?.account)
		XCTAssertEqual(client.findUser("bob")?.realName, "Bob")
	}

	func testJoinParametersAreIgnoredWithoutExtendedJoin() {
		let client = makeClient(named: "me")
		joinChannel("#chat", on: client)

		client.receiveJoin(message(
			":alice!a@example.org JOIN #chat alice_acct :Alice Liddell",
			on: client
		))

		let alice = client.findUser("alice")
		XCTAssertNotNil(alice)
		XCTAssertNil(alice?.account)
		XCTAssertNil(alice?.realName)
	}

	func testAccountTagAndBotTagUpdateSender() {
		let client = makeClient(named: "me")
		let channel = joinChannel("#chat", on: client)
		addUser(named: "alice", to: channel, on: client)

		client.receivePrivmsgAndNotice(message(
			"@account=alice_acct :alice!a@example.org PRIVMSG #chat :hi",
			on: client
		))

		XCTAssertEqual(client.findUser("alice")?.account, "alice_acct")
		XCTAssertFalse(client.findUser("alice")?.isBot ?? true)

		client.receivePrivmsgAndNotice(message(
			"@bot :alice!a@example.org NOTICE #chat :beep",
			on: client
		))

		XCTAssertTrue(client.findUser("alice")?.isBot ?? false)
		XCTAssertEqual(client.findUser("alice")?.account, "alice_acct")

		client.receiveTagMessage(message(
			"@account=other;+typing=active :alice!a@example.org TAGMSG #chat",
			on: client
		))

		XCTAssertEqual(client.findUser("alice")?.account, "other")
	}

	func testSetNameUpdatesRealName() {
		let client = makeClient(named: "me")
		let channel = joinChannel("#chat", on: client)
		addUser(named: "alice", to: channel, on: client)

		client.receiveSetName(message(":alice!a@example.org SETNAME :Alice P. Liddell", on: client))

		XCTAssertEqual(client.findUser("alice")?.realName, "Alice P. Liddell")
	}

	func testSetNameCommandRequiresCapability() {
		let client = makeClient(named: "me")
		client.markAsLoggedIn()

		client.sendCommand("SETNAME New Name", completeTarget: false, target: nil)

		XCTAssertEqual(client.sentLines.count, 0)
		XCTAssertEqual(client.printedLines.count, 1)

		client.enableCapability(.setName)
		client.sendCommand("SETNAME New Name", completeTarget: false, target: nil)

		XCTAssertEqual(sentLines(of: client), ["SETNAME :New Name"])
	}

	func testInviteForSomebodyElseIsPrintedInChannel() {
		let client = makeClient(named: "me")
		let channel = joinChannel("#chat", on: client)

		client.receiveInvite(message(":alice!a@example.org INVITE bob #chat", on: client))

		XCTAssertEqual(client.printedLines.count, 1)
		let printed = printedLine(at: 0, on: client)
		XCTAssertTrue(printed?["channel"] as? Channel === channel)
		XCTAssertEqual((printed?["lineType"] as? NSNumber)?.uintValue, TVCLogLineType.invite.rawValue)

		let body = printed?["messageBody"] as? String
		XCTAssertTrue(body?.contains("alice") ?? false)
		XCTAssertTrue(body?.contains("bob") ?? false)
		XCTAssertTrue(body?.contains("#chat") ?? false)

		client.receiveInvite(message(":alice!a@example.org INVITE bob #other", on: client))
		XCTAssertEqual(client.printedLines.count, 1)
	}

	func testInviteForMyselfStillUsesInvitePrompt() {
		let client = makeClient(named: "me")

		client.receiveInvite(message(":alice!a@example.org INVITE me #chat", on: client))

		XCTAssertEqual(client.printedLines.count, 1)
		let printed = printedLine(at: 0, on: client)
		XCTAssertNil(printed?["channel"])
		XCTAssertTrue((printed?["messageBody"] as? String)?.contains("invited you") ?? false)
	}

	func testWhoUsesWhoxWhenSupported() {
		let client = makeClient(named: "me")
		client.markAsLoggedIn()

		client.sendWho(toChannelNamed: "#chat")
		XCTAssertEqual(sentLines(of: client).last, "WHO #chat")

		client.supportInfo.processConfigurationData("WHOX")
		client.sendWho(toChannelNamed: "#chat")

		XCTAssertEqual(sentLines(of: client).last, "WHO #chat %tcuhnfar,152")
	}

	func testWhoxReplyIsParsed() {
		let client = makeClient(named: "me")
		client.supportInfo.processConfigurationData("WHOX BOT=B PREFIX=(ov)@+")
		let channel = joinChannel("#chat", on: client)

		client.receiveNumericReply(message(
			":irc.example.net 354 me 152 #chat ~alice host.example.org alice H*@B alice_acct :Alice",
			on: client
		))

		let alice = client.findUser("alice")
		XCTAssertEqual(alice?.username, "~alice")
		XCTAssertEqual(alice?.address, "host.example.org")
		XCTAssertEqual(alice?.realName, "Alice")
		XCTAssertEqual(alice?.account, "alice_acct")
		XCTAssertTrue(alice?.isIRCop ?? false)
		XCTAssertTrue(alice?.isBot ?? false)
		XCTAssertFalse(alice?.isAway ?? true)
		XCTAssertEqual(channel.findMember("alice")?.modes, "o")

		client.receiveNumericReply(message(
			":irc.example.net 354 me 152 #chat ~bob host.example.org bob G 0 :Bob",
			on: client
		))

		let bob = client.findUser("bob")
		XCTAssertNotNil(bob)
		XCTAssertNil(bob?.account)
		XCTAssertFalse(bob?.isIRCop ?? true)
		XCTAssertFalse(bob?.isBot ?? true)

		client.receiveNumericReply(message(
			":irc.example.net 354 me 999 #chat ~eve host eve H 0 :Eve",
			on: client
		))
		XCTAssertNil(client.findUser("eve"))
	}

	func testWhoReplyStillParsesWithoutWhox() {
		let client = makeClient(named: "me")
		client.supportInfo.processConfigurationData("PREFIX=(ov)@+")
		let channel = joinChannel("#chat", on: client)
		let existing = addUser(named: "alice", to: channel, on: client)

		client.modify(existing) { mutableUser in
			mutableUser.account = "kept"
		}

		client.receiveNumericReply(message(
			":irc.example.net 352 me #chat ~alice host.example.org irc.example.net alice H+ :0 Alice",
			on: client
		))

		let alice = client.findUser("alice")
		XCTAssertEqual(alice?.username, "~alice")
		XCTAssertEqual(alice?.realName, "Alice")
		XCTAssertEqual(alice?.account, "kept")
	}

	func testPreAwayIsRequestedAndRestoresAwayOnReconnect() {
		let client = makeClient(named: "me")

		client.receiveCapabilityOrAuthenticationRequest(message(
			":irc.example.net CAP * LS :pre-away",
			on: client
		))
		XCTAssertEqual(capabilityCommands(of: client), ["REQ pre-away"])

		client.receiveCapabilityOrAuthenticationRequest(message(
			":irc.example.net CAP me ACK :pre-away",
			on: client
		))

		XCTAssertTrue(client.isCapabilityEnabled(.preAway))
		XCTAssertEqual(capabilityCommands(of: client).last, "END")
		XCTAssertEqual(client.sentLines.count, 0)
	}

	func testPreAwaySendsAwayBeforeCapEndWhenReconnecting() {
		let client = makeClient(named: "me")
		client.markAsLoggedIn()
		client.toggleAwayStatus(true, withComment: "brb")
		XCTAssertEqual(sentLines(of: client), ["AWAY :brb"])

		client.sentLines.removeAllObjects()
		client.setValue(false, forKey: "isLoggedIn")
		client.connectType = .reconnect
		client.enableCapability(.preAway)
		client.sendNextQueuedCapability()

		XCTAssertEqual(sentLines(of: client), ["AWAY :brb"])
		XCTAssertEqual(capabilityCommands(of: client), ["END"])
	}

	func testPreAwayDoesNothingWithoutCapability() {
		let client = makeClient(named: "me")
		client.markAsLoggedIn()
		client.toggleAwayStatus(true, withComment: "brb")
		client.sentLines.removeAllObjects()
		client.setValue(false, forKey: "isLoggedIn")
		client.connectType = .reconnect
		client.sendNextQueuedCapability()

		XCTAssertEqual(client.sentLines.count, 0)
		XCTAssertEqual(capabilityCommands(of: client), ["END"])
	}

	private func makeClient(named nickname: String) -> GLTTestClient {
		let configuration: NSDictionary = ["nickname": nickname, "username": nickname]
		guard let configuration = configuration as? [String: Any] else {
			preconditionFailure("Test configuration must bridge to a Swift dictionary")
		}
		return GLTTestClient(configDictionary: configuration)
	}

	@discardableResult
	private func joinChannel(_ name: String, on client: GLTTestClient) -> Channel {
		let channel = client.findChannelOrCreate(name)!
		channel.activate()

		return channel
	}

	@discardableResult
	private func addUser(named nickname: String, to channel: Channel, on client: GLTTestClient) -> User {
		let user = client.findUserOrCreate(nickname)
		channel.addMember(ChannelUser(user: user))

		return user
	}

	private func message(_ line: String, on client: IRCClient) -> Message {
		Message(line: line, on: client)!
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
