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
import GlasstualPluginKit
import Testing

/// The IRCv3 extensions that change what an ordinary message means:
/// `server-time`, `echo-message`, `away-notify`, `account-notify`,
/// `account-tag`, `chghost`, `setname` and `standard-replies`.
@Suite("IRCv3 message extensions")
@MainActor
struct IRCSpecCapabilityBehaviourTests {
	private func client(nickname: String = "me") -> GLTTestClient {
		GLTTestClient(configDictionary: ["nickname": nickname, "username": nickname])
	}

	private func joinedChannel(_ name: String, on client: GLTTestClient) throws -> Channel {
		let channel = try #require(client.findChannelOrCreate(name))

		channel.activate()

		return channel
	}

	private func deliver(_ line: String, on client: GLTTestClient) throws {
		let message = try #require(Message(line: line, on: client))

		client.forwardsProcessedMessages = true
		client.processIncomingMessage(message)
	}

	private func printedChannelNames(of client: GLTTestClient) -> [String] {
		client.printedLines.compactMap { ($0 as? [String: Any])?["channel"] as? IRCChannel }.map(\.name)
	}

	// MARK: - server-time

	/// `server-time`: `<value> ::= YYYY-MM-DDThh:mm:ss.sssZ`. A message
	/// carrying one is historic — it happened when the tag says, not when it
	/// arrived.
	@Test("server-time: a conforming timestamp sets the message time")
	func serverTimeSetsTheMessageTime() throws {
		let client = client()

		client.enableCapability(.serverTime)

		let message = try #require(
			Message(line: "@time=2011-10-19T16:40:51.620Z :nick!u@h PRIVMSG #chan :hi", on: client)
		)

		#expect(message.isHistoric)
		#expect(abs(message.receivedAt.timeIntervalSince1970 - 1_319_042_451.620) < 0.001)
	}

	/// The tag is only meaningful once the capability is on: an unnegotiated
	/// `time` tag must not be allowed to backdate a live message.
	@Test("server-time: the tag is ignored without the capability")
	func serverTimeNeedsTheCapability() throws {
		let client = client()
		let before = Date()
		let message = try #require(
			Message(line: "@time=2011-10-19T16:40:51.620Z :nick!u@h PRIVMSG #chan :hi", on: client)
		)

		#expect(message.isHistoric == false)
		#expect(message.receivedAt.timeIntervalSince1970 >= before.timeIntervalSince1970)
	}

	/// A `time` tag the client cannot read must leave the arrival time alone
	/// rather than resolving to some other instant.
	@Test(
		"server-time: an unreadable timestamp leaves the arrival time alone",
		arguments: ["not-a-date", "2011-10-19T16:40:51+0200", "", ".", "1.2.3"]
	)
	func unreadableServerTimeIsIgnored(_ value: String) throws {
		let client = client()

		client.enableCapability(.serverTime)

		let message = try #require(
			Message(line: "@time=\(value) :nick!u@h PRIVMSG #chan :hi", on: client)
		)

		#expect(message.isHistoric == false)
	}

	/// Bouncers predating `server-time` send a Unix timestamp in a `t` tag,
	/// which the client still reads for their sake.
	@Test("server-time: a bouncer's Unix timestamp is still read")
	func unixTimestampTagIsRead() throws {
		let client = client()

		client.enableCapability(.serverTime)

		let message = try #require(
			Message(line: "@t=1319042451.620 :nick!u@h PRIVMSG #chan :hi", on: client)
		)

		#expect(message.isHistoric)
		#expect(abs(message.receivedAt.timeIntervalSince1970 - 1_319_042_451.620) < 0.001)
	}

	// MARK: - echo-message

	/// `echo-message`: the server sends our own PRIVMSG back to us. It has to
	/// be filed under the target we sent it to, not under our own nickname, or
	/// every outgoing private message opens a window named after ourselves.
	@Test("echo-message: an echoed private message lands in the target's window")
	func echoedPrivateMessageLandsInTheTargetWindow() throws {
		let client = client(nickname: "me")

		client.enableCapability(.echoMessage)

		let query = try #require(client.findChannelOrCreate("bob", as: .privateMessage))

		query.activate()

		try deliver(":me!u@h PRIVMSG bob :hello there", on: client)

		#expect(printedChannelNames(of: client) == ["bob"])
	}

	/// `echo-message` also applies to CTCP: our own query coming back is not a
	/// query from someone else and must not be answered a second time.
	@Test("echo-message: an echoed CTCP query is not answered")
	func echoedCTCPQueryIsNotAnswered() throws {
		let client = client(nickname: "me")

		client.enableCapability(.echoMessage)

		try deliver(":me!u@h PRIVMSG bob :\u{01}VERSION\u{01}", on: client)

		#expect(client.sentLines.count == 0)
	}

	// MARK: - away-notify

	/// `away-notify`: `AWAY :<message>` marks the sender away, and a bare
	/// `AWAY` marks them back.
	@Test("away-notify: AWAY with and without a message toggles the away flag")
	func awayNotifyTogglesTheAwayFlag() throws {
		let client = client()
		let channel = try joinedChannel("#chan", on: client)

		client.enableCapability(.awayNotify)

		try deliver(":alice!ali@example.org JOIN #chan", on: client)
		try deliver(":alice!ali@example.org AWAY :out to lunch", on: client)

		#expect(try #require(channel.findMember("alice")).user.isAway)

		try deliver(":alice!ali@example.org AWAY", on: client)

		#expect(try #require(channel.findMember("alice")).user.isAway == false)
	}

	/// Without the capability the client has no reason to believe an `AWAY`
	/// about somebody else, so the flag stays where it was.
	@Test("away-notify: AWAY about another user is ignored without the capability")
	func awayNotifyNeedsTheCapability() throws {
		let client = client()
		let channel = try joinedChannel("#chan", on: client)

		try deliver(":alice!ali@example.org JOIN #chan", on: client)
		try deliver(":alice!ali@example.org AWAY :out to lunch", on: client)

		#expect(try #require(channel.findMember("alice")).user.isAway == false)
	}

	// MARK: - account-notify and account-tag

	/// `account-notify`: `ACCOUNT <accountname>` names the account the user
	/// just logged into, and `*` means they logged out.
	@Test("account-notify: ACCOUNT sets and clears the account")
	func accountNotifySetsAndClears() throws {
		let client = client()

		client.enableCapability(.accountNotify)

		let channel = try joinedChannel("#chan", on: client)

		try deliver(":alice!ali@example.org JOIN #chan", on: client)
		try deliver(":alice!ali@example.org ACCOUNT aliceacct", on: client)

		#expect(try #require(channel.findMember("alice")).user.account == "aliceacct")

		try deliver(":alice!ali@example.org ACCOUNT *", on: client)

		#expect(try #require(channel.findMember("alice")).user.account == nil)
	}

	/// `account-tag`: an `account` tag on any message names the sender's
	/// account without a separate ACCOUNT message.
	@Test("account-tag: the account tag identifies the sender")
	func accountTagIdentifiesTheSender() throws {
		let client = client()
		let channel = try joinedChannel("#chan", on: client)

		try deliver(":alice!ali@example.org JOIN #chan", on: client)
		try deliver("@account=aliceacct :alice!ali@example.org PRIVMSG #chan :hi", on: client)

		#expect(try #require(channel.findMember("alice")).user.account == "aliceacct")
	}

	// MARK: - chghost

	/// `chghost`: `CHGHOST <newuser> <newhost>` replaces both halves of the
	/// sender's hostmask in place, without a QUIT/JOIN pair.
	@Test("chghost: CHGHOST replaces the user and host")
	func changeHostReplacesUserAndHost() throws {
		let client = client()

		client.enableCapability(.changeHost)

		let channel = try joinedChannel("#chan", on: client)

		try deliver(":alice!ali@example.org JOIN #chan", on: client)
		try deliver(":alice!ali@example.org CHGHOST newuser cloak.example.net", on: client)

		let alice = try #require(channel.findMember("alice"))

		#expect(alice.user.username == "newuser")
		#expect(alice.user.address == "cloak.example.net")
	}

	/// A `CHGHOST` naming something that cannot be a user or host is a
	/// malformed message, and applying half of it would leave the member with
	/// a hostmask that matches nothing.
	@Test("chghost: a malformed CHGHOST changes nothing")
	func malformedChangeHostIsRejected() throws {
		let client = client()

		client.enableCapability(.changeHost)

		let channel = try joinedChannel("#chan", on: client)

		try deliver(":alice!ali@example.org JOIN #chan", on: client)
		try deliver(":alice!ali@example.org CHGHOST new user cloak.example.net", on: client)

		let alice = try #require(channel.findMember("alice"))

		#expect(alice.user.username == "ali")
		#expect(alice.user.address == "example.org")
	}

	// MARK: - setname

	/// `setname`: `SETNAME :<realname>` updates the sender's real name.
	@Test("setname: SETNAME updates the real name")
	func setNameUpdatesTheRealName() throws {
		let client = client()

		client.enableCapability(.setName)

		let channel = try joinedChannel("#chan", on: client)

		try deliver(":alice!ali@example.org JOIN #chan", on: client)
		try deliver(":alice!ali@example.org SETNAME :Alice of Example", on: client)

		#expect(try #require(channel.findMember("alice")).user.realName == "Alice of Example")
	}

	/// Each of these messages only exists because its capability was
	/// negotiated, so an unnegotiated one rewrites nothing -- the same rule
	/// `away-notify` already followed.
	@Test("account-notify, chghost and setname are ignored without their capability")
	func identityMessagesNeedTheirCapability() throws {
		let client = client()
		let channel = try joinedChannel("#chan", on: client)

		try deliver(":alice!ali@example.org JOIN #chan", on: client)
		try deliver(":alice!ali@example.org ACCOUNT aliceacct", on: client)
		try deliver(":alice!ali@example.org CHGHOST newuser cloak.example.net", on: client)
		try deliver(":alice!ali@example.org SETNAME :Someone Else", on: client)

		let alice = try #require(channel.findMember("alice"))

		#expect(alice.user.account == nil)
		#expect(alice.user.username == "ali")
		#expect(alice.user.address == "example.org")
		#expect(alice.user.realName == nil)
	}

	// MARK: - standard-replies

	/// `standard-replies`: `FAIL|WARN|NOTE <command> <code> [context...] :<description>`.
	/// All three are recognised, and the command they are about is the first
	/// parameter, not the reply's own name.
	@Test(
		"standard-replies: FAIL, WARN and NOTE are all recognised",
		arguments: ["FAIL", "WARN", "NOTE"]
	)
	func standardRepliesAreRecognised(_ command: String) throws {
		let client = client()
		let before = client.printedLines.count

		try deliver(
			":irc.example.net \(command) ACC REG_INVALID_CALLBACK :Email address is invalid",
			on: client
		)

		#expect(client.printedLines.count > before)
	}

	/// A standard reply naming a channel in its context is reported in that
	/// channel rather than the console.
	@Test("standard-replies: a channel in the context routes the reply there")
	func standardRepliesRouteToTheirChannel() throws {
		let client = client()

		_ = try joinedChannel("#chan", on: client)

		try deliver(
			":irc.example.net FAIL CHATHISTORY MESSAGE_ERROR #chan :Messages could not be retrieved",
			on: client
		)

		#expect(printedChannelNames(of: client) == ["#chan"])
	}

	/// A standard reply is at least `<command> <code> <description>`; anything
	/// shorter cannot be read without taking the code from the wrong field.
	@Test("standard-replies: a short reply is ignored")
	func shortStandardRepliesAreIgnored() throws {
		let client = client()
		let before = client.printedLines.count

		try deliver(":irc.example.net FAIL :something went wrong", on: client)

		#expect(client.printedLines.count == before)
	}
}
