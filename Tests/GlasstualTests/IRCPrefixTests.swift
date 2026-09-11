/*  *********************************************************************
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

@testable import Glasstual
import Testing

@MainActor
@Suite("IRC prefix")
struct IRCPrefixTests {
	@Test("A default prefix is empty rather than nil")
	func defaultsAreNonnullableEmptyStrings() {
		let prefix = Prefix()

		#expect(prefix.isServer == false)

		#expect(prefix.nickname == "")
		#expect(prefix.hostmask == "")

		#expect(prefix.username == nil)
		#expect(prefix.address == nil)
	}

	@Test("A user prefix parsed from the wire keeps every component")
	func parsedUserPrefixKeepsEveryComponent() throws {
		let message = try #require(Message(line: ":nick!user@host PRIVMSG #channel :hello"))

		#expect(message.sender.nickname == "nick")
		#expect(message.sender.username == "user")
		#expect(message.sender.address == "host")
		#expect(message.sender.hostmask == "nick!user@host")
		#expect(message.sender.isServer == false)
	}

	@Test("A server prefix is marked as one")
	func serverPrefixIsMarked() throws {
		let message = try #require(Message(line: ":irc.example.net 001 me :Welcome"))

		#expect(message.sender.isServer)
		#expect(message.sender.nickname == "irc.example.net")
		#expect(message.sender.username == nil)
	}

	/** RFC 2812 2.3.1 writes the prefix as
	 `servername / ( nickname [ [ "!" user ] "@" host ] )`, so a bare nickname
	 is a legal prefix — a server relaying a NICK or a QUIT it generated itself
	 sends one. Read as a server name, the message reached no ignore rule, no
	 notification and no query. */
	@Test("A bare nickname prefix names a user")
	func bareNicknamePrefixIsAUser() throws {
		let message = try #require(Message(line: ":alice NICK :alice2"))

		#expect(message.sender.isServer == false)
		#expect(message.sender.nickname == "alice")
		#expect(message.sender.username == nil)
		#expect(message.sender.address == nil)
		#expect(message.sender.hostmask == "alice")
	}

	/// A server name carries a dot, which the nickname grammar has no room for,
	/// so the two stay apart.
	@Test("A dotted prefix with no host is still a server")
	func dottedPrefixWithoutAHostIsAServer() throws {
		let message = try #require(Message(line: ":services. NOTICE me :hello"))

		#expect(message.sender.isServer)
		#expect(message.sender.nickname == "services.")
	}

	/** `nick!@host`: the username half is empty, which the hostmask grammar
	 refuses. The person is still named, and taking the whole string as a server
	 name filed their message in the console. */
	@Test("A hostmask with an empty username still names its user")
	func emptyUsernameHostmaskNamesItsUser() throws {
		let message = try #require(Message(line: ":alice!@example.org PRIVMSG #chan :hello"))

		#expect(message.sender.isServer == false)
		#expect(message.sender.nickname == "alice")
		#expect(message.sender.username == nil)
		#expect(message.sender.address == "example.org")
	}

	/// A "!" with an unusable username behind it is not recoverable: reading
	/// the nickname out of it would accept a prefix the grammar rejects.
	@Test("A hostmask whose username is unusable stays a server")
	func unparsableUsernameStaysAServer() throws {
		let message = try #require(
			Message(line: ":alice!\(String(repeating: "u", count: 41))@example.org PRIVMSG #chan :hi")
		)

		#expect(message.sender.isServer)
	}

	/** `Prefix` used to be an immutable class with a mutable subclass, so two
	 prefixes carrying the same hostmask were two objects. Equality is
	 structural now, and every field takes part in it — including `isServer`,
	 which is what keeps a server notice apart from a user of the same name. */
	@Test("Equality and hashing take every field into account")
	func equalityAndHashUseAllFields() {
		let prefix = Prefix(nickname: "nick", username: "user", address: "host", hostmask: "nick!user@host")
		let same = Prefix(nickname: "nick", username: "user", address: "host", hostmask: "nick!user@host")

		#expect(prefix == same)
		#expect(prefix.hashValue == same.hashValue)

		#expect(
			prefix != Prefix(
				nickname: "nick",
				username: "user",
				address: "host",
				hostmask: "nick!user@host",
				isServer: true
			)
		)
		#expect(
			prefix != Prefix(nickname: "other", username: "user", address: "host", hostmask: "nick!user@host")
		)
		#expect(
			prefix != Prefix(nickname: "nick", username: "other", address: "host", hostmask: "nick!user@host")
		)
		#expect(
			prefix != Prefix(nickname: "nick", username: "user", address: "other", hostmask: "nick!user@host")
		)
		#expect(prefix != Prefix(nickname: "nick", username: "user", address: "host", hostmask: "other"))
	}
}
