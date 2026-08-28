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

/// RFC 2812 §3.6 and §5.1: the WHO and WHOIS replies, and the WHOX extension
/// modern.ircdocs.horse documents as `RPL_WHOSPCRPL` (354).
@Suite("WHO and WHOIS replies")
@MainActor
struct IRCSpecWhoTests {
	private func client() -> GLTTestClient {
		GLTTestClient(configDictionary: ["nickname": "me", "username": "me"])
	}

	private func joinedChannel(_ name: String, on client: GLTTestClient) throws -> Channel {
		let channel = try #require(client.findChannelOrCreate(name))

		channel.activate()

		return channel
	}

	private func receive(_ line: String, on client: GLTTestClient) throws {
		let message = try #require(Message(line: line, on: client))

		client.receiveNumericReply(message)
	}

	/// RFC 2812 §5.1 RPL_WHOREPLY: `<client> <channel> <user> <host> <server>
	/// <nick> <flags> :<hopcount> <real name>`. Reading any field at the wrong
	/// index would attach another user's host to this one.
	@Test("352 is read at the field positions RFC 2812 defines")
	func whoReplyFieldsAreReadInOrder() throws {
		let client = client()
		let channel = try joinedChannel("#chan", on: client)

		try receive(
			":irc.example.net 352 me #chan ali example.org irc.example.net alice H :0 Alice Example",
			on: client
		)

		let alice = try #require(channel.findMember("alice"))

		#expect(alice.user.username == "ali")
		#expect(alice.user.address == "example.org")
		#expect(alice.user.realName == "Alice Example")
	}

	/// The last parameter is `<hopcount> <real name>`, so the hop count has to
	/// come off before the real name is kept.
	@Test("352: the hop count is not part of the real name")
	func hopCountIsNotPartOfTheRealName() throws {
		let client = client()
		let channel = try joinedChannel("#chan", on: client)

		try receive(
			":irc.example.net 352 me #chan b example.net irc.example.net bob H :3 Bob of Example",
			on: client
		)

		#expect(try #require(channel.findMember("bob")).user.realName == "Bob of Example")
	}

	/// RFC 2812 §5.1: the flags are `<H|G>[*][@|+]`. `G` is gone (away), `*`
	/// is an IRC operator, and the rest are channel prefixes.
	@Test("352: the flags field carries away, operator and prefix status")
	func whoFlagsAreParsed() {
		let modeForPrefix: (String) -> String? = { prefix in
			switch prefix {
			case "@": "o"
			case "+": "v"
			default: nil
			}
		}

		let away = IRCWHOFlags.parse(
			"G@", monitorAwayStatus: true, botFlagSupported: false, modeForPrefix: modeForPrefix
		)

		#expect(away.isAway)
		#expect(away.userModes == "o")

		let here = IRCWHOFlags.parse(
			"H+", monitorAwayStatus: true, botFlagSupported: false, modeForPrefix: modeForPrefix
		)

		#expect(here.isAway == false)
		#expect(here.userModes == "v")

		let operatorFlags = IRCWHOFlags.parse(
			"H*@", monitorAwayStatus: true, botFlagSupported: false, modeForPrefix: modeForPrefix
		)

		#expect(operatorFlags.isIRCop)
		#expect(operatorFlags.userModes == "o")
	}

	/// The `B` flag only means "bot" on a server that advertises `BOT=` in
	/// ISUPPORT; elsewhere it is just another prefix character.
	@Test("352: the bot flag needs the ISUPPORT BOT token")
	func botFlagNeedsTheISupportToken() {
		let supported = IRCWHOFlags.parse(
			"HB", monitorAwayStatus: false, botFlagSupported: true, modeForPrefix: { _ in nil }
		)
		let unsupported = IRCWHOFlags.parse(
			"HB", monitorAwayStatus: false, botFlagSupported: false, modeForPrefix: { _ in nil }
		)

		#expect(supported.isBot)
		#expect(unsupported.isBot == false)
	}

	/// A short 352 cannot be read at the indices the reply defines, so it says
	/// nothing rather than something wrong.
	@Test("352: a short reply is ignored")
	func shortWhoRepliesAreIgnored() throws {
		let client = client()
		let channel = try joinedChannel("#chan", on: client)

		try receive(":irc.example.net 352 me #chan ali example.org irc.example.net alice", on: client)

		#expect(channel.numberOfMembers == 0)
	}

	/// modern.ircdocs.horse RPL_WHOSPCRPL: the reply carries back the token
	/// the client put in its `WHO ... %tcuhnfar,<token>` request, and only a
	/// reply carrying that token has the field layout the client asked for.
	@Test("354: a WHOX reply carries the client's own token and the account")
	func whoxRepliesCarryTheAccount() throws {
		let client = client()
		let channel = try joinedChannel("#chan", on: client)
		let token = IRCServerQuirks.whoxResponseToken

		try receive(
			":irc.example.net 354 me \(token) #chan ali example.org alice H aliceacct :Alice Example",
			on: client
		)

		let alice = try #require(channel.findMember("alice"))

		#expect(alice.user.account == "aliceacct")
		#expect(alice.user.username == "ali")
		#expect(alice.user.realName == "Alice Example")
	}

	/// A 354 answering somebody else's request has a different field layout,
	/// so reading it would put the wrong values on the member.
	@Test("354: a reply with another token is not read as a member update")
	func whoxRepliesWithAnotherTokenAreNotRead() throws {
		let client = client()
		let channel = try joinedChannel("#chan", on: client)

		try receive(
			":irc.example.net 354 me 999 #chan ali example.org alice H aliceacct :Alice Example",
			on: client
		)

		#expect(channel.numberOfMembers == 0)
	}

	/// `account-tag` and WHOX agree on what "no account" looks like: the
	/// literal `0` in a WHOX reply, like `*` elsewhere.
	@Test("354: 0 means the user has no account")
	func whoxZeroMeansNoAccount() throws {
		let client = client()
		let channel = try joinedChannel("#chan", on: client)
		let token = IRCServerQuirks.whoxResponseToken

		try receive(
			":irc.example.net 354 me \(token) #chan b example.net bob H 0 :Bob Example",
			on: client
		)

		#expect(try #require(channel.findMember("bob")).user.account == nil)
	}

	/// RFC 2812 §5.1 RPL_WHOISUSER: `<client> <nick> <user> <host> * :<real name>`.
	@Test("311 opens a WHOIS response")
	func whoisUserOpensTheResponse() throws {
		let client = client()

		try receive(":irc.example.net 311 me alice ali example.org * :Alice Example", on: client)

		#expect(client.inWhoisResponse)

		try receive(":irc.example.net 318 me alice :End of /WHOIS list", on: client)

		#expect(client.inWhoisResponse == false)
	}

	/// RFC 2812 §5.1 RPL_ENDOFWHO closes the WHO request the client opened, so
	/// the next reply is not mistaken for part of this one.
	@Test("315 closes the WHO request")
	func endOfWhoClosesTheRequest() throws {
		let client = client()

		client.requestedCommands.recordWhoRequestOpenedAsVisible()

		#expect(client.requestedCommands.visibleWhoRequest)

		try receive(":irc.example.net 315 me #chan :End of /WHO list", on: client)

		#expect(client.requestedCommands.visibleWhoRequest == false)
	}
}
