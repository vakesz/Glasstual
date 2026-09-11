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
	private func makeClient(waitsForNickServ: Bool = true, joinDelay: TimeInterval = 0) -> GLTTestClient {
		var preferences = ClientPreferences()
		preferences.autojoinDelayAfterIdentification = joinDelay
		let client = GLTTestClient(
			configDictionary: ["autojoinWaitsForNickServ": waitsForNickServ],
			nicknamePassword: nil,
			fixture: GLTClientEnvironmentFixture(preferences: preferences)
		)
		client.userNickname = "swift-user"
		client.markAsLoggedIn()
		client.forwardsProcessedMessages = true
		client.startup.requiresAuthentication = waitsForNickServ
		client.startup.commands = .ready
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

	private func registeredIdentificationClient() throws -> GLTTestClient {
		let client = GLTTestClient(configDictionary: ["onConnectCommands": ["msg NickServ IDENTIFY secret"]])
		client.userNickname = "swift-user"
		client.isConnected = true
		client.forwardsProcessedMessages = true
		_ = try #require(client.findChannelOrCreate("#swift"))
		try receive(":irc.example.org 001 swift-user :Welcome", on: client)
		return client
	}

	@Test("Authentication confirmation and timeout bypass the legacy global delay", arguments: [true, false])
	func authenticationResolutionJoinsImmediately(confirmed: Bool) throws {
		let client = makeClient(joinDelay: 17)
		defer { client.stopAllTimers(); client.cancelPendingSessionTasks() }
		_ = try #require(client.findChannelOrCreate("#swift"))
		if confirmed {
			try receive(Self.identifiedNotice, on: client)
		} else {
			client.noteNickServIdentificationWritten()
			client.authenticationDeadlineExpired(for: client.startup.identifier)
		}
		#expect(joinLines(of: client).count == 1)
	}

	@Test("Quit cancels authentication before the transport grace period")
	func quitCancelsAuthenticationImmediately() throws {
		let client = try registeredIdentificationClient()
		client.noteNickServIdentificationWritten()
		let identifier = client.startup.identifier
		client.quit(withComment: "bye")
		defer { client.cancelDelayedDisconnect(); client.stopAllTimers() }
		#expect(client.startup.authenticationTask == nil)
		client.authenticationDeadlineExpired(for: identifier)
		#expect(joinLines(of: client).isEmpty)
	}

	@Test("A welcome received while disconnecting cannot restart connect commands")
	func welcomeDuringDisconnectIsIgnored() throws {
		let client = GLTTestClient(configDictionary: ["onConnectCommands": ["msg NickServ IDENTIFY secret"]])
		client.userNickname = "swift-user"
		client.isConnected = true
		client.isDisconnecting = true
		try receive(":irc.example.org 001 swift-user :Welcome", on: client)
		#expect(!client.isLoggedIn)
		#expect(!client.didPerformConnectCommands)
		#expect(client.sentLines.count == 0)
	}

	/// 001 starts the long unattended wait; the identification write replaces
	/// it with the short one. Either deadline falls back to joining exactly once.
	@Test("The identification write replaces the unattended deadline, and falls back only once")
	func deadlineStartsWhenWritten() throws {
		let client = try registeredIdentificationClient()
		defer { client.stopAllTimers(); client.cancelPendingSessionTasks() }
		let identifier = client.startup.identifier
		let unattendedDeadline = try #require(client.startup.authenticationTask)
		#expect(client.startup.authentication == .waiting)
		client.noteNickServIdentificationWritten()
		let writeDeadline = try #require(client.startup.authenticationTask)
		#expect(unattendedDeadline.isCancelled)
		#expect(writeDeadline.isCancelled == false)
		#expect(joinLines(of: client).isEmpty)
		try receive(":NickServ!NickServ@services. NOTICE swift-user :Invalid password", on: client)
		#expect(joinLines(of: client).isEmpty)
		client.authenticationDeadlineExpired(for: identifier)
		client.authenticationDeadlineExpired(for: identifier)
		try receive(Self.identifiedNotice, on: client)
		#expect(joinLines(of: client).count == 1)
		#expect(client.startup.authenticationTask == nil)
	}

	@Test("Cancelling startup makes old deadlines harmless")
	func cancelledDeadlineCannotReleaseAnotherSession() throws {
		let client = try registeredIdentificationClient()
		client.noteNickServIdentificationWritten()
		let oldIdentifier = client.startup.identifier
		client.cancelPendingSessionTasks()
		client.isLoggedIn = false
		try receive(":irc.example.org 001 swift-user :Welcome again", on: client)
		client.noteNickServIdentificationWritten()
		defer { client.stopAllTimers(); client.cancelPendingSessionTasks() }
		client.authenticationDeadlineExpired(for: oldIdentifier)
		#expect(joinLines(of: client).isEmpty)
		try receive(Self.identifiedNotice, on: client)
		#expect(joinLines(of: client).count == 1)
	}

	@Test("Identification cannot be confirmed by another user's numeric or an untrusted notice",
	      arguments: [":irc.example.org 900 other other!u@h other :logged in",
	                  ":NickServ!u@ordinary-user.test NOTICE swift-user :You are now identified",
	                  ":NickServ!NickServ@services. NOTICE someone-else :You are now identified"])
	func rejectsUnrelatedConfirmation(_ line: String) throws {
		let client = try registeredIdentificationClient()
		defer { client.stopAllTimers(); client.cancelPendingSessionTasks() }
		try receive(line, on: client)
		#expect(joinLines(of: client).isEmpty)
	}

	@Test("NickServ command recognition uses command structure",
	      arguments: ["msg bob IDENTIFY secret", "raw JOIN #NickServ", "msg NickServ HELP IDENTIFY",
	                  "msg #channel NickServ IDENTIFY secret", "raw PRIVMSG NickServ :IDENTIFY"])
	func doesNotGateUnrelatedCommands(_ command: String) {
		#expect(!IRCStartupCommandPolicy.identifiesNickServ(command))
	}

	@Test("Account confirmation before welcome cannot consume autojoin")
	func authenticationBeforeWelcome() throws {
		let client = makeClient()
		client.isLoggedIn = false
		client.cancelConnectCommandSettling()
		client.isConnected = true
		_ = try #require(client.findChannelOrCreate("#swift"))
		try receive(Self.loggedInNumeric, on: client)
		#expect(!client.isAutojoined)
		#expect(joinLines(of: client).isEmpty)
		try receive(":irc.example.org 001 swift-user :Welcome", on: client)
		#expect(joinLines(of: client).count == 1)
	}

	@Test("Configured identification waits for confirmation even without the old wait option",
	      arguments: ["msg NickServ IDENTIFY secret", "/raw PRIVMSG NickServ :IDENTIFY secret",
	                  "quote PRIVMSG NickServ :IDENTIFY swift-user secret"])
	func configuredIdentificationWaits(_ command: String) throws {
		let client = GLTTestClient(configDictionary: ["onConnectCommands": [command]])
		client.userNickname = "swift-user"
		client.forwardsProcessedMessages = true
		client.isConnected = true
		_ = try #require(client.findChannelOrCreate("#swift"))
		try receive(":irc.example.org 001 swift-user :Welcome", on: client)
		#expect(joinLines(of: client).isEmpty)
		try receive(Self.identifiedNotice, on: client)
		#expect(joinLines(of: client).count == 1)
	}

	@Test("DumaNet Hungarian confirmation releases identification")
	func hungarianConfirmation() throws {
		let client = try holdingClient()
		try receive(
			":NickServ!NickServ@services. NOTICE swift-user :Jelszavad elfogadva - azonosítás sikeres.",
			on: client
		)
		#expect(joinLines(of: client).count == 1)
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

	@Test("Cancelling a pending join preserves an already completed autojoin")
	func cancellationPreservesCompletedJoin() throws {
		let client = try holdingClient()
		try receive(Self.identifiedNotice, on: client)
		client.cancelPendingAutojoin()
		#expect(client.isAutojoined)
		try receive(Self.loggedInNumeric, on: client)
		#expect(joinLines(of: client).count == 1)
	}
}
