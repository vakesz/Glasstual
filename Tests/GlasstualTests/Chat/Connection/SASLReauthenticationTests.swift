// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing

/// SASL 3.2 re-authentication on a registered connection: it never pauses
/// negotiation, never ends the connection, and a failure keeps the account.
@MainActor
@Suite("SASL re-authentication")
struct SASLReauthenticationTests {
	private func session(
		offering mechanisms: [String] = ["SCRAM-SHA-256", "PLAIN"],
		acknowledged: Bool = true,
		identified: Bool = true,
		configuration: [String: Any] = [:]
	) -> TestServerSession {
		let session = TestServerSession(
			configDictionary: ["nickname": "me", "username": "me", "usesSASL": true].merging(configuration) { $1 },
			nicknamePassword: "secret"
		)
		session.userNickname = "me"
		session.setConnectionTransportForTesting(.connected)
		session.capabilityNegotiation.offer("sasl", values: mechanisms)
		if acknowledged {
			_ = session.capabilityNegotiation.acknowledge("sasl")
		}
		session.markAsLoggedIn()
		if identified {
			session.enableCapability(.isIdentifiedWithSASL)
			session.identity.account = "old"
			session.sasl.lastAuthenticatedMechanism = .plain
		}
		return session
	}

	private func receive(_ line: String, on session: TestServerSession) throws {
		let message = try #require(Message(line: line, on: session))
		if message.commandNumeric > 0, let numeric = ServerNumeric(rawValue: message.commandNumeric) {
			session.handleAuthenticationTrackingNumeric(numeric, message: message, shouldPrint: false)
		} else {
			session.handleCapabilityOrAuthenticationRequest(message)
		}
	}

	private func sent(by session: TestServerSession) -> [String] {
		(session.sentLines as NSArray).compactMap { $0 as? String }
	}

	private func printed(by session: TestServerSession) -> [String] {
		(session.printedLines as NSArray).compactMap { ($0 as? [String: Any])?["messageBody"] as? String }
	}

	@Test("Signing in again sends AUTHENTICATE without pausing negotiation")
	func beginsWithoutPausing() {
		let session = session()
		defer { session.stopAllTimers() }

		#expect(session.beginSASLReauthentication(using: nil) == nil)

		#expect(sent(by: session).last == "AUTHENTICATE SCRAM-SHA-256")
		#expect(session.capabilityNegotiation.isPaused == false)
		#expect(session.isCapabilityEnabled(.isInSASLNegotiation))
		#expect(session.isCapabilityEnabled(.isIdentifiedWithSASL) == false)
		#expect(session.sasl.status == .inProgress(.scramSHA256))
	}

	@Test("Success records the new account and mechanism")
	func successRecordsAccount() throws {
		let session = session()
		defer { session.stopAllTimers() }

		#expect(session.beginSASLReauthentication(using: .plain) == nil)
		try receive(":irc.example.net AUTHENTICATE +", on: session)
		#expect(sent(by: session).last == "AUTHENTICATE " + Data("me\0me\0secret".utf8).base64EncodedString())
		try receive(":irc.example.net 900 me me!u@h new :You are now logged in as new", on: session)
		try receive(":irc.example.net 903 me :SASL authentication successful", on: session)

		#expect(session.identity.account == "new")
		#expect(session.sasl.lastAuthenticatedMechanism == .plain)
		#expect(session.isCapabilityEnabled(.isIdentifiedWithSASL))
		#expect(session.sasl.phase == .registration)
		#expect(session.sasl.status == .succeeded(account: "new", mechanism: .plain))
		#expect(printed(by: session).last == String(localized: .IRC.saslReauthenticationSucceeded("new", "PLAIN")))
	}

	@Test("A refused explicit mechanism gets no fallback, never quits and keeps the account")
	func failureKeepsTheAccount() throws {
		let session = session(configuration: ["disconnectOnSASLFailure": true])
		defer { session.stopAllTimers() }

		#expect(session.beginSASLReauthentication(using: .scramSHA256) == nil)
		try receive(":irc.example.net 904 me :SASL authentication failed", on: session)

		#expect(sent(by: session).contains("AUTHENTICATE PLAIN") == false)
		#expect(session.isQuitting == false)
		#expect(session.isCapabilityEnabled(.isInSASLNegotiation) == false)
		#expect(session.isCapabilityEnabled(.isIdentifiedWithSASL))
		#expect(printed(by: session).last == String(localized: .IRC.saslReauthenticationFailedKeptAccount("old")))
	}

	@Test("Automatic choice falls back to the next mechanism after a refusal")
	func automaticFallsBack() throws {
		let session = session()
		defer { session.stopAllTimers() }

		session.beginSASLReauthentication(using: nil)
		try receive(":irc.example.net 904 me :SASL authentication failed", on: session)

		#expect(sent(by: session).last == "AUTHENTICATE PLAIN")
	}

	@Test("907 says the server does not allow it and keeps the account")
	func alreadyAuthenticatedIsNotAllowed() throws {
		let session = session()
		defer { session.stopAllTimers() }

		session.beginSASLReauthentication(using: .plain)
		try receive(":irc.example.net 907 me :You have already authenticated using SASL", on: session)

		#expect(printed(by: session).contains(String(localized: .IRC.saslReauthenticationNotAllowed)))
		#expect(session.isCapabilityEnabled(.isIdentifiedWithSASL))
		#expect(session.identity.account == "old")
	}

	@Test("Refusals: not registered, in progress, not offered, unusable")
	func refusals() {
		let unregistered = TestServerSession(configDictionary: [:], nicknamePassword: "secret")
		#expect(unregistered.beginSASLReauthentication(using: nil) == .notRegistered)

		let session = session()
		defer { session.stopAllTimers() }
		#expect(session.beginSASLReauthentication(using: .external) == .mechanismNotOffered(.external))

		let withExternal = self.session(offering: ["EXTERNAL", "PLAIN"])
		#expect(withExternal.beginSASLReauthentication(using: .external) == .mechanismUnavailable(.external, .noClientCertificate))

		#expect(session.beginSASLReauthentication(using: nil) == nil)
		#expect(session.beginSASLReauthentication(using: nil) == .exchangeInProgress)

		let unoffered = TestServerSession(configDictionary: [:], nicknamePassword: "secret")
		unoffered.markAsLoggedIn()
		#expect(unoffered.beginSASLReauthentication(using: nil) == .saslNotOffered)
	}

	@Test("An unacknowledged sasl is requested first and the exchange starts on the ACK")
	func requestsSASLFirst() throws {
		let session = session(acknowledged: false, identified: false)
		defer { session.stopAllTimers() }

		#expect(session.beginSASLReauthentication(using: nil) == nil)
		#expect((session.sentCapabilityCommands as NSArray).contains("REQ sasl"))
		#expect(session.canBeginSASLReauthentication == false)

		try receive(":irc.example.net CAP me ACK :sasl", on: session)

		#expect(sent(by: session).last == "AUTHENTICATE SCRAM-SHA-256")
		#expect(session.capabilityNegotiation.isPaused == false)
	}

	@Test("A refused sasl request reports and clears the pending sign-in")
	func refusedRequestClears() throws {
		let session = session(acknowledged: false, identified: false)
		session.beginSASLReauthentication(using: nil)

		try receive(":irc.example.net CAP me NAK :sasl", on: session)

		#expect(session.sasl.pendingReauthentication == nil)
		#expect(session.sasl.status == .failed(reason: String(localized: .IRC.saslStatusNotOffered)))
	}

	@Test("A failure during registration still disconnects when asked to")
	func registrationFailureStillDisconnects() throws {
		let session = TestServerSession(
			configDictionary: ["nickname": "me", "usesSASL": true, "disconnectOnSASLFailure": true],
			nicknamePassword: "secret"
		)
		defer { session.stopAllTimers() }
		session.setConnectionTransportForTesting(.connected)
		try receive(":irc.example.net CAP * LS :sasl=PLAIN", on: session)
		try receive(":irc.example.net CAP * ACK :sasl", on: session)
		try receive(":irc.example.net 904 me :SASL authentication failed", on: session)

		#expect(printed(by: session).contains(String(localized: .IRC.saslAuthenticationFailedDisconnecting)))
	}
}

/// cap-notify: SASL re-offered after registration (sasl-3.2).
@MainActor
@Suite("SASL re-offered after registration")
struct SASLCapabilityNotifyTests {
	private func session(identified: Bool, automatic: Bool = true) -> TestServerSession {
		let session = TestServerSession(
			configDictionary: ["nickname": "me", "usesSASL": true, "saslReauthenticatesAutomatically": automatic],
			nicknamePassword: "secret"
		)
		session.setConnectionTransportForTesting(.connected)
		session.capabilityNegotiation.offer("sasl", values: ["EXTERNAL"])
		_ = session.capabilityNegotiation.acknowledge("sasl")
		session.markAsLoggedIn()
		if identified {
			session.enableCapability(.isIdentifiedWithSASL)
			session.sasl.lastAuthenticatedMechanism = .plain
		}
		return session
	}

	private func receive(_ line: String, on session: TestServerSession) throws {
		try session.handleCapabilityOrAuthenticationRequest(#require(Message(line: line, on: session)))
	}

	private func sent(by session: TestServerSession) -> [String] {
		(session.sentLines as NSArray).compactMap { $0 as? String }
	}

	private func printed(by session: TestServerSession) -> [String] {
		(session.printedLines as NSArray).compactMap { ($0 as? [String: Any])?["messageBody"] as? String }
	}

	@Test("A usable mechanism re-offered to a session that is not signed in signs it in")
	func reofferedSignsIn() throws {
		let session = session(identified: false)
		defer { session.stopAllTimers() }

		try receive(":irc.example.net CAP me NEW :sasl=PLAIN,SCRAM-SHA-256", on: session)

		#expect(sent(by: session).last == "AUTHENTICATE SCRAM-SHA-256")
	}

	@Test("With the setting off nothing happens")
	func settingOffDoesNothing() throws {
		let session = session(identified: false, automatic: false)

		try receive(":irc.example.net CAP me NEW :sasl=PLAIN,SCRAM-SHA-256", on: session)

		#expect(sent(by: session).contains { $0.hasPrefix("AUTHENTICATE") } == false)
	}

	@Test("A signed-in session only hears about a stronger mechanism")
	func signedInHearsAboutStronger() throws {
		let session = session(identified: true)

		try receive(":irc.example.net CAP me NEW :sasl=PLAIN", on: session)
		#expect(printed(by: session).isEmpty)

		try receive(":irc.example.net CAP me NEW :sasl=PLAIN,SCRAM-SHA-512", on: session)

		#expect(sent(by: session).contains { $0.hasPrefix("AUTHENTICATE") } == false)
		#expect(printed(by: session).last == String(localized: .IRC.saslStrongerMechanismOffered("SCRAM-SHA-512")))
	}

	@Test("CAP DEL sasl during re-authentication ends it without quitting")
	func withdrawalEndsReauthentication() throws {
		let session = session(identified: true)
		session.capabilityNegotiation.offer("sasl", values: ["PLAIN"])
		session.config.disconnectOnSASLFailure = true
		session.beginSASLReauthentication(using: nil)
		try #require(session.isCapabilityEnabled(.isInSASLNegotiation))

		try receive(":irc.example.net CAP me DEL :sasl", on: session)

		#expect(session.isCapabilityEnabled(.isInSASLNegotiation) == false)
		#expect(session.isCapabilityEnabled(.isIdentifiedWithSASL))
		#expect(session.isQuitting == false)
	}
}
