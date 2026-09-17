// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

@testable import Glasstual
import Testing

/// ZNC's `buffextras` module replays joins, parts, mode changes and the rest as
/// ordinary chat, and the client turns them back into the events they describe
/// before anything else reads the line. The rewriting is what these pin.
@MainActor
@Suite("ZNC bouncer interception")
struct ClientZNCTests {
	private func client() -> TestClient {
		let client = TestClient()
		client.znc.isConnected = true
		return client
	}

	private func intercepted(_ line: String, on client: TestClient) throws -> Message? {
		let message = try #require(Message(line: line, on: client))
		return client.interceptZNCServerInput(message)
	}

	private func replay(_ body: String, on client: TestClient) throws -> Message? {
		try intercepted(":*buffextras!znc@znc.in PRIVMSG #chat :\(body)", on: client)
	}

	@Test("A replayed join becomes a JOIN from the person who joined")
	func replayedJoinBecomesAJoin() throws {
		let client = client()
		let rewritten = try #require(try replay("alice!user@host joined", on: client))

		#expect(rewritten.command == "JOIN")
		#expect(rewritten.params == ["#chat"])
		#expect(rewritten.sender.nickname == "alice")
		#expect(rewritten.sender.username == "user")
		#expect(rewritten.sender.address == "host")
		#expect(rewritten.sender.isServer == false)
		#expect(rewritten.isPrintOnlyMessage)
	}

	@Test("A replayed nickname change carries the new nickname as its parameter")
	func replayedNickChangeCarriesTheNewNickname() throws {
		let client = client()
		let rewritten = try #require(try replay("alice!user@host is now known as alicia", on: client))

		#expect(rewritten.command == "NICK")
		#expect(rewritten.params == ["#chat", "alicia"])
	}

	@Test(
		"A replayed part carries its comment in either spelling",
		arguments: [
			("alice!user@host parted with message: [so long]", "so long"),
			("alice!user@host parted: so long", "so long"),
			("alice!user@host parted with message: []", ""),
		]
	)
	func replayedPartCarriesItsComment(_ replayed: (line: String, comment: String)) throws {
		let client = client()
		let rewritten = try #require(try replay(replayed.line, on: client))

		#expect(rewritten.command == "PART")
		#expect(rewritten.params == ["#chat", replayed.comment])
	}

	@Test(
		"A replayed quit carries its comment in either spelling",
		arguments: [
			("alice!user@host quit with message: [bye]", "bye"),
			("alice!user@host quit: bye", "bye"),
		]
	)
	func replayedQuitCarriesItsComment(_ replayed: (line: String, comment: String)) throws {
		let client = client()
		let rewritten = try #require(try replay(replayed.line, on: client))

		#expect(rewritten.command == "QUIT")
		#expect(rewritten.params == ["#chat", replayed.comment])
	}

	@Test(
		"A replayed kick carries its target and, where there is one, its reason",
		arguments: [
			("alice!user@host kicked bob with reason: rude", ["#chat", "bob", "rude"]),
			("alice!user@host kicked bob Reason: [rude]", ["#chat", "bob", "rude"]),
			("alice!user@host kicked bob Reason: []", ["#chat", "bob"]),
		]
	)
	func replayedKickCarriesItsTargetAndReason(_ replayed: (line: String, params: [String])) throws {
		let client = client()
		let rewritten = try #require(try replay(replayed.line, on: client))

		#expect(rewritten.command == "KICK")
		#expect(rewritten.params == replayed.params)
	}

	/// The mode string and each of its arguments are separate IRC parameters.
	/// Joining them made "+ov nick1 nick2" one parameter, which the MODE
	/// handler cannot read.
	@Test("A replayed mode change splits its arguments into parameters of their own")
	func replayedModeChangeSplitsItsArguments() throws {
		let client = client()
		let rewritten = try #require(try replay("alice!user@host set mode: +ov bob carol", on: client))

		#expect(rewritten.command == "MODE")
		#expect(rewritten.params == ["#chat", "+ov", "bob", "carol"])
	}

	@Test("A replayed topic change is dropped, because the server sends the topic itself")
	func replayedTopicChangeIsDropped() throws {
		let client = client()

		#expect(try replay("alice!user@host changed the topic to: hello", on: client) == nil)
	}

	@Test("A replay of the local user's own event is dropped")
	func replayOfTheLocalUserIsDropped() throws {
		let client = client()
		client.userNickname = "me"

		#expect(try replay("me!user@host joined", on: client) == nil)
	}

	/// A token that is not a hostmask names the server, not a person.
	@Test("A replay whose first token is not a hostmask is attributed to the server")
	func replayFromAServerKeepsItsName() throws {
		let client = client()
		let rewritten = try #require(try replay("irc.example.net set mode: +n", on: client))

		#expect(rewritten.command == "MODE")
		#expect(rewritten.sender.nickname == "irc.example.net")
		#expect(rewritten.sender.isServer)
	}

	/// The module's own text is not an event, so it is shown as it arrived,
	/// attributed to whoever the replay names.
	@Test("Replayed text that describes no event is printed as it arrived")
	func unrecognisedReplayIsPrintedAsItArrived() throws {
		let client = client()
		let rewritten = try #require(try replay("alice!user@host did something new", on: client))

		#expect(rewritten.command == "PRIVMSG")
		#expect(rewritten.params == ["#chat", "alice!user@host did something new"])
		#expect(rewritten.sender.nickname == "alice")
		#expect(rewritten.isPrintOnlyMessage)
	}

	@Test("A playback module's buffer-cleared notice is dropped while the capability is on")
	func playbackBufferClearedNoticeIsDropped() throws {
		let client = client()
		client.capabilityNegotiation.enable(.zncPlaybackModule)
		let line = ":*playback!znc@znc.in PRIVMSG me :" +
			"The playback buffer for [user] channels matching [*] has been cleared."

		#expect(try intercepted(line, on: client) == nil)
	}

	@Test("Nothing is intercepted when the connection is not a ZNC bouncer")
	func nothingIsInterceptedOffZNC() throws {
		let client = TestClient()
		let message = try #require(
			Message(line: ":*buffextras!znc@znc.in PRIVMSG #chat :alice!user@host joined", on: client)
		)

		#expect(client.interceptZNCServerInput(message) === message)
	}
}
