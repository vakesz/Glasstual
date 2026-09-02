/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import Foundation
@testable import Glasstual
import Testing

/** `IRCNicknameRetryPolicy` decides which nickname comes next; this is the
 wiring that gets a 433 off the wire and a `NICK` back onto it. A registration
 that stalls here leaves the client connected and never logged in, which is
 exactly the state a user cannot get out of without quitting.

 The 437 case is here too because `ERR_UNAVAILRESOURCE` means a nickname on one
 server and a channel on another; only the nickname reading may retry. */
@MainActor
@Suite("Nickname collision retry")
struct IRCClientNicknameCollisionTests {
	private func registeringClient() -> GLTTestClient {
		let client = GLTTestClient(configDictionary: ["nickname": "mara", "username": "mara"])
		client.config.alternateNicknames = ["mara-alt", "mara-alt2"]
		client.isConnected = true

		return client
	}

	private func sentLines(of client: GLTTestClient) -> [String] {
		(client.sentLines as NSArray).compactMap { $0 as? String }
	}

	private func collision(_ nickname: String, on client: IRCClient) throws -> Message {
		try #require(
			Message(line: ":irc.example.net 433 * \(nickname) :Nickname is already in use", on: client)
		)
	}

	@Test("A 433 during registration sends the next configured alternate")
	func collisionSendsTheNextAlternate() throws {
		let client = registeringClient()

		try client.receiveNumericReply(collision("mara", on: client))

		#expect(sentLines(of: client) == ["NICK mara-alt"])

		try client.receiveNumericReply(collision("mara-alt", on: client))

		#expect(sentLines(of: client) == ["NICK mara-alt", "NICK mara-alt2"])
	}

	/// Once the configured list is spent the nickname is padded instead, so a
	/// server that refuses every alternate still converges.
	@Test("A 433 after the alternates run out pads the last nickname")
	func collisionPadsOnceTheAlternatesAreSpent() throws {
		let client = registeringClient()

		for nickname in ["mara", "mara-alt", "mara-alt2"] {
			try client.receiveNumericReply(collision(nickname, on: client))
		}

		#expect(sentLines(of: client) == ["NICK mara-alt", "NICK mara-alt2", "NICK mara-alt2_"])
	}

	/// After registration a 433 is somebody else's `/nick` failing, and the
	/// client must report it rather than rename the user.
	@Test("A 433 after login is reported and changes nothing")
	func collisionAfterLoginDoesNotRetry() throws {
		let client = registeringClient()
		client.markAsLoggedIn()

		try client.receiveNumericReply(collision("someone", on: client))

		#expect(client.sentLines.count == 0)
	}

	@Test("A 433 that arrives while disconnected is not answered")
	func collisionWhileDisconnectedDoesNothing() throws {
		let client = registeringClient()
		client.isConnected = false

		try client.receiveNumericReply(collision("mara", on: client))

		#expect(client.sentLines.count == 0)
	}

	/// `437` is `ERR_UNAVAILRESOURCE`: a retry only when the resource named is
	/// a nickname. A channel name there is a join failure, not a rename.
	@Test("A 437 retries for a nickname and not for a channel")
	func unavailableResourceRetriesOnlyForANickname() throws {
		let client = registeringClient()

		let nicknameUnavailable = try #require(
			Message(line: ":irc.example.net 437 * mara :Nick/channel is temporarily unavailable", on: client)
		)
		client.receiveNumericReply(nicknameUnavailable)

		#expect(sentLines(of: client) == ["NICK mara-alt"])

		let channelUnavailable = try #require(
			Message(line: ":irc.example.net 437 * #chat :Nick/channel is temporarily unavailable", on: client)
		)
		client.receiveNumericReply(channelUnavailable)

		#expect(sentLines(of: client) == ["NICK mara-alt"])
	}
}
