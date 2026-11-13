// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation
@testable import Glasstual
import Testing

/// SASL OAUTHBEARER on a live session: the token goes out once, over TLS
/// only, and a refused token falls back to the next mechanism.
@MainActor
@Suite("SASL OAUTHBEARER exchange", .timeLimit(.minutes(1)))
struct ServerSessionOAuthBearerTests {
	private static let token = "vF9dft4qmT"

	private func session(securedValidatingChain validatingChain: Bool?) async throws -> TestServerSession {
		let session = TestServerSession(configDictionary: ["nickname": "me", "usesSASL": true], nicknamePassword: "secret")
		session.config.pendingSASLBearerToken = .set(Self.token)
		session.setConnectionTransportForTesting(.connected)
		guard let validatingChain else { return session }
		var config = ConnectionConfig()
		config.serverAddress = "irc.example.test"
		config.serverPort = 6697
		config.connectionShouldValidateCertificateChain = validatingChain
		let connection = Connection(config: config, onSession: session)
		session.socket = connection
		connection.callbackReceiver.didSecureConnection(
			withProtocolType: .TLSv13,
			cipherSuite: tlsCipherSuiteUnknown,
			leafCertificate: Data("certificate the user saw".utf8)
		)
		try await Eventually.until("TLS to come up") { connection.isSecured }
		return session
	}

	private func receive(_ line: String, on session: TestServerSession) throws {
		let message = try #require(Message(line: line, on: session))
		if let numeric = ServerNumeric(rawValue: message.commandNumeric), message.commandNumeric > 0 {
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

	private var expectedResponse: String {
		let message = "n,,\u{01}host=irc.example.test\u{01}port=6697\u{01}auth=Bearer \(Self.token)\u{01}\u{01}"
		return "AUTHENTICATE " + Data(message.utf8).base64EncodedString()
	}

	private func start(on session: TestServerSession) throws {
		try receive(":irc.example.test CAP * LS :sasl=OAUTHBEARER,SCRAM-SHA-256", on: session)
		try receive(":irc.example.test CAP * ACK :sasl", on: session)
	}

	@Test("A trusted connection sends the token and signs in")
	func successfulExchange() async throws {
		let session = try await session(securedValidatingChain: true)
		defer { session.stopAllTimers() }

		try start(on: session)
		#expect(sent(by: session).last == "AUTHENTICATE OAUTHBEARER")

		try receive(":irc.example.test AUTHENTICATE +", on: session)
		#expect(sent(by: session).last == expectedResponse)

		try receive(":irc.example.test 900 me me!u@h account :You are now logged in as account", on: session)
		try receive(":irc.example.test 903 me :SASL authentication successful", on: session)

		#expect(session.isCapabilityEnabled(.isIdentifiedWithSASL))
		#expect(session.sasl.lastAuthenticatedMechanism == .oauthBearer)
		#expect(session.identity.account == "account")
	}

	@Test("A refused token is acknowledged, reported and followed by SCRAM")
	func refusedTokenFallsBack() async throws {
		let session = try await session(securedValidatingChain: true)
		defer { session.stopAllTimers() }

		try start(on: session)
		try receive(":irc.example.test AUTHENTICATE +", on: session)
		let error = Data(#"{"status":"invalid_token"}"#.utf8).base64EncodedString()
		try receive(":irc.example.test AUTHENTICATE \(error)", on: session)
		#expect(sent(by: session).last == "AUTHENTICATE AQ==")

		try receive(":irc.example.test 904 me :SASL authentication failed", on: session)

		#expect(printed(by: session).contains(ConnectionSafetyStrings.SASL.oauthTokenRejected(status: "invalid_token")))
		#expect(sent(by: session).last == "AUTHENTICATE SCRAM-SHA-256")
		#expect(session.sasl.oauthExchange == nil)
	}

	@Test("Over plaintext OAUTHBEARER is never named on the wire")
	func plaintextNeverNamesTheMechanism() async throws {
		let session = try await session(securedValidatingChain: nil)
		defer { session.stopAllTimers() }

		try start(on: session)

		#expect(sent(by: session).contains("AUTHENTICATE OAUTHBEARER") == false)
		#expect(sent(by: session).last == "AUTHENTICATE SCRAM-SHA-256")
	}

	@Test("An unchecked chain holds the token until the user allows the host")
	func uncheckedChainWaitsForConsent() async throws {
		let session = try await session(securedValidatingChain: false)
		defer { session.stopAllTimers() }
		session.recordedOutput.responseAnswer = .alternate

		try start(on: session)
		#expect(sent(by: session).last == "AUTHENTICATE OAUTHBEARER")

		try receive(":irc.example.test AUTHENTICATE +", on: session)
		try await Eventually.until("the token after consent") { sent(by: session).last == expectedResponse }
		#expect(session.recordedOutput.responseRequests.count == 1)
	}
}
