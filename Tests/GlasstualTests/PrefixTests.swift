// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

@testable import Glasstual
import Testing

@MainActor
@Suite("IRC prefix")
struct PrefixTests {
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
}
