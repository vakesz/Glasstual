// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing

/** `autojoinWaitsForNickServ` holds the autojoin until the network confirms
 the identification, however that confirmation arrives: the NickServ notice
 that answers an identification this session sent and is waiting on, the same
 notice answering one it did not send itself -- a connect command's -- or the
 `900` numeric a network that tracks accounts sends alongside it. */
@MainActor
@Suite("Autojoin waiting for identification")
struct ServerSessionAutojoinIdentificationTests {
	private func makeSession(waitsForNickServ: Bool = true, joinDelay: TimeInterval = 0) -> TestServerSession {
		var settings = ChatSettings()
		settings.autojoinDelayAfterIdentification = joinDelay
		let session = TestServerSession(
			configDictionary: ["autojoinWaitsForNickServ": waitsForNickServ],
			nicknamePassword: nil,
			fixture: ChatEnvironmentFixture(settings: settings)
		)
		session.userNickname = "swift-user"
		session.markAsLoggedIn()
		session.forwardsProcessedMessages = true
		session.startup.requiresAuthentication = waitsForNickServ
		session.startup.commands = .ready
		return session
	}

	private func receive(_ line: String, on session: TestServerSession) throws {
		let message = try #require(Message(line: line, on: session))
		if message.commandNumeric > 0 {
			session.receiveNumericReply(message)
		} else {
			session.processIncomingMessage(message)
		}
	}

	private func joinLines(of session: TestServerSession) -> [String] {
		session.sentLines.compactMap { $0 as? String }.filter { $0.hasPrefix("JOIN") }
	}

	private static let registeredNotice = ":NickServ!NickServ@services. NOTICE swift-user :This nickname is registered. "
		+ "Please choose a different nickname, or identify via /msg NickServ IDENTIFY swift-user <password>"
	private static let identifiedNotice =
		":NickServ!NickServ@services. NOTICE swift-user :You are now identified for \u{02}swift-user\u{02}."
	private static let loggedInNumeric =
		":irc.example.org 900 swift-user swift-user!~user@example.test swift-user :You are now logged in as swift-user"

	/** Before anything confirms the identification the autojoin has to wait,
	 whichever path is going to end the wait. The registered notice is what
	 tells the session the network has a NickServ at all; with no password on
	 file nothing is sent back, which is the connect-command case: the
	 identification went out through a command, so the session is not waiting
	 on a reply of its own. */
	private func holdingSession(waitsForNickServ: Bool = true) throws -> TestServerSession {
		let session = makeSession(waitsForNickServ: waitsForNickServ)
		_ = try #require(session.findConversationOrCreate("#swift"))
		try receive(Self.registeredNotice, on: session)
		#expect(session.nickServ.isWaiting == false)
		if waitsForNickServ {
			session.performAutoJoin()
			#expect(joinLines(of: session).isEmpty)
			#expect(session.isAutojoined == false)
		}
		return session
	}

	private func registeredIdentificationSession() throws -> TestServerSession {
		let session = TestServerSession(configDictionary: ["loginCommands": ["msg NickServ IDENTIFY secret"]])
		session.userNickname = "swift-user"
		session.isConnected = true
		session.forwardsProcessedMessages = true
		_ = try #require(session.findConversationOrCreate("#swift"))
		try receive(":irc.example.org 001 swift-user :Welcome", on: session)
		return session
	}

	@Test("Authentication confirmation and timeout bypass the legacy global delay", arguments: [true, false])
	func authenticationResolutionJoinsImmediately(confirmed: Bool) throws {
		let session = makeSession(joinDelay: 17)
		defer { session.stopAllTimers(); session.cancelPendingSessionTasks() }
		_ = try #require(session.findConversationOrCreate("#swift"))
		if confirmed {
			try receive(Self.identifiedNotice, on: session)
		} else {
			session.noteNickServIdentificationWritten()
			session.authenticationDeadlineExpired(for: session.startup.identifier)
		}
		#expect(joinLines(of: session).count == 1)
	}

	@Test("Quit cancels authentication before the transport grace period")
	func quitCancelsAuthenticationImmediately() throws {
		let session = try registeredIdentificationSession()
		session.noteNickServIdentificationWritten()
		let identifier = session.startup.identifier
		session.quit(withComment: "bye")
		defer { session.cancelDelayedDisconnect(); session.stopAllTimers() }
		#expect(session.startup.authenticationTask == nil)
		session.authenticationDeadlineExpired(for: identifier)
		#expect(joinLines(of: session).isEmpty)
	}

	@Test("A welcome received while disconnecting cannot restart connect commands")
	func welcomeDuringDisconnectIsIgnored() throws {
		let session = TestServerSession(configDictionary: ["loginCommands": ["msg NickServ IDENTIFY secret"]])
		session.userNickname = "swift-user"
		session.isConnected = true
		session.isDisconnecting = true
		try receive(":irc.example.org 001 swift-user :Welcome", on: session)
		#expect(!session.isLoggedIn)
		#expect(!session.didPerformConnectCommands)
		#expect(session.sentLines.count == 0)
	}

	/// 001 starts the long unattended wait; the identification write replaces
	/// it with the short one. Either deadline falls back to joining exactly once.
	@Test("The identification write replaces the unattended deadline, and falls back only once")
	func deadlineStartsWhenWritten() throws {
		let session = try registeredIdentificationSession()
		defer { session.stopAllTimers(); session.cancelPendingSessionTasks() }
		let identifier = session.startup.identifier
		let unattendedDeadline = try #require(session.startup.authenticationTask)
		#expect(session.startup.authentication == .waiting)
		session.noteNickServIdentificationWritten()
		let writeDeadline = try #require(session.startup.authenticationTask)
		#expect(unattendedDeadline.isCancelled)
		#expect(writeDeadline.isCancelled == false)
		#expect(joinLines(of: session).isEmpty)
		try receive(":NickServ!NickServ@services. NOTICE swift-user :Invalid password", on: session)
		#expect(joinLines(of: session).isEmpty)
		session.authenticationDeadlineExpired(for: identifier)
		session.authenticationDeadlineExpired(for: identifier)
		try receive(Self.identifiedNotice, on: session)
		#expect(joinLines(of: session).count == 1)
		#expect(session.startup.authenticationTask == nil)
	}

	@Test("Cancelling startup makes old deadlines harmless")
	func cancelledDeadlineCannotReleaseAnotherSession() throws {
		let session = try registeredIdentificationSession()
		session.noteNickServIdentificationWritten()
		let oldIdentifier = session.startup.identifier
		session.cancelPendingSessionTasks()
		session.isLoggedIn = false
		try receive(":irc.example.org 001 swift-user :Welcome again", on: session)
		session.noteNickServIdentificationWritten()
		defer { session.stopAllTimers(); session.cancelPendingSessionTasks() }
		session.authenticationDeadlineExpired(for: oldIdentifier)
		#expect(joinLines(of: session).isEmpty)
		try receive(Self.identifiedNotice, on: session)
		#expect(joinLines(of: session).count == 1)
	}

	@Test("Identification cannot be confirmed by another user's numeric or an untrusted notice",
	      arguments: [":irc.example.org 900 other other!u@h other :logged in",
	                  ":NickServ!u@ordinary-user.test NOTICE swift-user :You are now identified",
	                  ":NickServ!NickServ@services. NOTICE someone-else :You are now identified"])
	func rejectsUnrelatedConfirmation(_ line: String) throws {
		let session = try registeredIdentificationSession()
		defer { session.stopAllTimers(); session.cancelPendingSessionTasks() }
		try receive(line, on: session)
		#expect(joinLines(of: session).isEmpty)
	}

	@Test("NickServ command recognition uses command structure",
	      arguments: ["msg bob IDENTIFY secret", "raw JOIN #NickServ", "msg NickServ HELP IDENTIFY",
	                  "msg #channel NickServ IDENTIFY secret", "raw PRIVMSG NickServ :IDENTIFY"])
	func doesNotGateUnrelatedCommands(_ command: String) {
		#expect(!StartupCommandPolicy.identifiesNickServ(command))
	}

	@Test("Account confirmation before welcome cannot consume autojoin")
	func authenticationBeforeWelcome() throws {
		let session = makeSession()
		session.isLoggedIn = false
		session.cancelConnectCommandSettling()
		session.isConnected = true
		_ = try #require(session.findConversationOrCreate("#swift"))
		try receive(Self.loggedInNumeric, on: session)
		#expect(!session.isAutojoined)
		#expect(joinLines(of: session).isEmpty)
		try receive(":irc.example.org 001 swift-user :Welcome", on: session)
		#expect(joinLines(of: session).count == 1)
	}

	@Test("Configured identification waits for confirmation even without the old wait option",
	      arguments: ["msg NickServ IDENTIFY secret", "/raw PRIVMSG NickServ :IDENTIFY secret",
	                  "quote PRIVMSG NickServ :IDENTIFY swift-user secret"])
	func configuredIdentificationWaits(_ command: String) throws {
		let session = TestServerSession(configDictionary: ["loginCommands": [command]])
		session.userNickname = "swift-user"
		session.forwardsProcessedMessages = true
		session.isConnected = true
		_ = try #require(session.findConversationOrCreate("#swift"))
		try receive(":irc.example.org 001 swift-user :Welcome", on: session)
		#expect(joinLines(of: session).isEmpty)
		try receive(Self.identifiedNotice, on: session)
		#expect(joinLines(of: session).count == 1)
	}

	@Test("DumaNet Hungarian confirmation releases identification")
	func hungarianConfirmation() throws {
		let session = try holdingSession()
		try receive(
			":NickServ!NickServ@services. NOTICE swift-user :Jelszavad elfogadva - azonosítás sikeres.",
			on: session
		)
		#expect(joinLines(of: session).count == 1)
	}

	@Test("A success notice the session was not waiting on releases the autojoin")
	func nickServNoticeReleasesUnrequestedIdentification() throws {
		let session = try holdingSession()

		try receive(Self.identifiedNotice, on: session)

		#expect(session.nickServ.isConfirmed)
		#expect(joinLines(of: session).contains { $0.contains("#swift") })
	}

	/// Without the option the join is owed to the end of registration, and
	/// the account reply must not bring it forward.
	@Test("A logged-in numeric does not start an autojoin that is not waiting")
	func loggedInNumericLeavesAnUnwaitedAutojoinAlone() throws {
		let session = try holdingSession(waitsForNickServ: false)

		try receive(Self.loggedInNumeric, on: session)

		#expect(joinLines(of: session).isEmpty)
		#expect(session.isAutojoined == false)
	}

	@Test("A logged-in numeric releases the autojoin")
	func loggedInNumericReleasesAutojoin() throws {
		let session = try holdingSession()

		try receive(Self.loggedInNumeric, on: session)

		#expect(joinLines(of: session).contains { $0.contains("#swift") })
	}

	@Test("A second confirmation does not join twice")
	func confirmationsDoNotJoinTwice() throws {
		let session = try holdingSession()

		try receive(Self.identifiedNotice, on: session)
		try receive(Self.loggedInNumeric, on: session)

		#expect(joinLines(of: session).filter { $0.contains("#swift") }.count == 1)
	}

	@Test("Cancelling a pending join preserves an already completed autojoin")
	func cancellationPreservesCompletedJoin() throws {
		let session = try holdingSession()
		try receive(Self.identifiedNotice, on: session)
		session.cancelPendingAutojoin()
		#expect(session.isAutojoined)
		try receive(Self.loggedInNumeric, on: session)
		#expect(joinLines(of: session).count == 1)
	}
}
