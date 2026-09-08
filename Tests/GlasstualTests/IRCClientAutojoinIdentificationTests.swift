/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import Foundation
@testable import Glasstual
import Testing

/** `autojoinWaitsForNickServ` holds the autojoin until the network confirms
 the identification, however that confirmation arrives: the NickServ notice
 that answers an identification this client sent and is waiting on, the same
 notice answering one it did not send itself -- a connect command's -- or the
 `900` numeric a network that tracks accounts sends alongside it. */
@MainActor
@Suite("Autojoin waiting for identification")
struct IRCClientAutojoinIdentificationTests {
	private func makeClient(waitsForNickServ: Bool = true) -> GLTTestClient {
		let client = GLTTestClient(
			configDictionary: ["autojoinWaitsForNickServ": waitsForNickServ],
			nicknamePassword: nil,
			fixture: GLTClientEnvironmentFixture(preferences: ClientPreferences())
		)
		client.userNickname = "swift-user"
		client.markAsLoggedIn()
		client.forwardsProcessedMessages = true
		return client
	}

	private func receive(_ line: String, on client: GLTTestClient) throws {
		let message = try #require(Message(line: line, on: client))
		if message.commandNumeric > 0 {
			client.receiveNumericReply(message)
		} else {
			client.processIncomingMessage(message)
		}
	}

	private func joinLines(of client: GLTTestClient) -> [String] {
		client.sentLines.compactMap { $0 as? String }.filter { $0.hasPrefix("JOIN") }
	}

	private static let registeredNotice = ":NickServ!NickServ@services. NOTICE swift-user :This nickname is registered. "
		+ "Please choose a different nickname, or identify via /msg NickServ IDENTIFY swift-user <password>"
	private static let identifiedNotice =
		":NickServ!NickServ@services. NOTICE swift-user :You are now identified for \u{02}swift-user\u{02}."
	private static let loggedInNumeric =
		":irc.example.org 900 swift-user swift-user!~user@example.test swift-user :You are now logged in as swift-user"

	/** Before anything confirms the identification the autojoin has to wait,
	 whichever path is going to end the wait. The registered notice is what
	 tells the client the network has a NickServ at all; with no password on
	 file nothing is sent back, which is the connect-command case: the
	 identification went out through a command, so the client is not waiting
	 on a reply of its own. */
	private func holdingClient(waitsForNickServ: Bool = true) throws -> GLTTestClient {
		let client = makeClient(waitsForNickServ: waitsForNickServ)
		_ = try #require(client.findChannelOrCreate("#swift"))
		try receive(Self.registeredNotice, on: client)
		#expect(client.isWaitingForNickServ == false)
		if waitsForNickServ {
			client.performAutoJoin()
			#expect(joinLines(of: client).isEmpty)
			#expect(client.isAutojoined == false)
		}
		return client
	}

	@Test("A success notice the client was not waiting on releases the autojoin")
	func nickServNoticeReleasesUnrequestedIdentification() throws {
		let client = try holdingClient()

		try receive(Self.identifiedNotice, on: client)

		#expect(client.userIsIdentifiedWithNickServ)
		#expect(joinLines(of: client).contains { $0.contains("#swift") })
	}

	/// Without the option the join is owed to the end of registration, and
	/// the account reply must not bring it forward.
	@Test("A logged-in numeric does not start an autojoin that is not waiting")
	func loggedInNumericLeavesAnUnwaitedAutojoinAlone() throws {
		let client = try holdingClient(waitsForNickServ: false)

		try receive(Self.loggedInNumeric, on: client)

		#expect(joinLines(of: client).isEmpty)
		#expect(client.isAutojoined == false)
	}

	@Test("A logged-in numeric releases the autojoin")
	func loggedInNumericReleasesAutojoin() throws {
		let client = try holdingClient()

		try receive(Self.loggedInNumeric, on: client)

		#expect(joinLines(of: client).contains { $0.contains("#swift") })
	}

	@Test("A second confirmation does not join twice")
	func confirmationsDoNotJoinTwice() throws {
		let client = try holdingClient()

		try receive(Self.identifiedNotice, on: client)
		try receive(Self.loggedInNumeric, on: client)

		#expect(joinLines(of: client).filter { $0.contains("#swift") }.count == 1)
	}
}
