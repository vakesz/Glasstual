// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing

/** `NicknameRetryPolicy` decides which nickname comes next; this is the
 wiring that gets a 433 off the wire and a `NICK` back onto it. A registration
 that stalls here leaves the session connected and never logged in, which is
 exactly the state a user cannot get out of without quitting.

 The 437 case is here too because `ERR_UNAVAILRESOURCE` means a nickname on one
 server and a channel on another; only the nickname reading may retry. */
@MainActor
@Suite("Nickname collision retry")
struct ServerSessionNicknameCollisionTests {
	private func registeringSession() -> TestServerSession {
		let session = TestServerSession(configDictionary: ["nickname": "mara", "username": "mara"])
		session.config.alternateNicknames = ["mara-alt", "mara-alt2"]
		session.isConnected = true

		return session
	}

	private func sentLines(of session: TestServerSession) -> [String] {
		(session.sentLines as NSArray).compactMap { $0 as? String }
	}

	private func collision(_ nickname: String, on session: ServerSession) throws -> Message {
		try #require(
			Message(line: ":irc.example.net 433 * \(nickname) :Nickname is already in use", on: session)
		)
	}

	@Test("A 433 during registration sends the next configured alternate")
	func collisionSendsTheNextAlternate() throws {
		let session = registeringSession()

		try session.receiveNumericReply(collision("mara", on: session))

		#expect(sentLines(of: session) == ["NICK mara-alt"])

		try session.receiveNumericReply(collision("mara-alt", on: session))

		#expect(sentLines(of: session) == ["NICK mara-alt", "NICK mara-alt2"])
	}

	/// Once the configured list is spent the nickname is padded instead, so a
	/// server that refuses every alternate still converges.
	@Test("A 433 after the alternates run out pads the last nickname")
	func collisionPadsOnceTheAlternatesAreSpent() throws {
		let session = registeringSession()

		for nickname in ["mara", "mara-alt", "mara-alt2"] {
			try session.receiveNumericReply(collision(nickname, on: session))
		}

		#expect(sentLines(of: session) == ["NICK mara-alt", "NICK mara-alt2", "NICK mara-alt2_"])
	}

	/// After registration a 433 is somebody else's `/nick` failing, and the
	/// session must report it rather than rename the user.
	@Test("A 433 after login is reported and changes nothing")
	func collisionAfterLoginDoesNotRetry() throws {
		let session = registeringSession()
		session.markAsLoggedIn()

		try session.receiveNumericReply(collision("someone", on: session))

		#expect(session.sentLines.count == 0)
	}

	@Test("A 433 that arrives while disconnected is not answered")
	func collisionWhileDisconnectedDoesNothing() throws {
		let session = registeringSession()
		session.isConnected = false

		try session.receiveNumericReply(collision("mara", on: session))

		#expect(session.sentLines.count == 0)
	}

	/// `437` is `ERR_UNAVAILRESOURCE`: a retry only when the resource named is
	/// a nickname. A channel name there is a join failure, not a rename.
	@Test("A 437 retries for a nickname and not for a channel")
	func unavailableResourceRetriesOnlyForANickname() throws {
		let session = registeringSession()

		let nicknameUnavailable = try #require(
			Message(line: ":irc.example.net 437 * mara :Nick/channel is temporarily unavailable", on: session)
		)
		session.receiveNumericReply(nicknameUnavailable)

		#expect(sentLines(of: session) == ["NICK mara-alt"])

		let channelUnavailable = try #require(
			Message(line: ":irc.example.net 437 * #chat :Nick/channel is temporarily unavailable", on: session)
		)
		session.receiveNumericReply(channelUnavailable)

		#expect(sentLines(of: session) == ["NICK mara-alt"])
	}
}
