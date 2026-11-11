// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation
@testable import Glasstual
import Testing

/// `REGISTER` and `VERIFY` carry a new password, so they pass the gate SASL
/// `PLAIN` passes, and nothing goes out on a connection that may not carry it.
@MainActor
@Suite("Account registration credential gate", .timeLimit(.minutes(1)))
struct AccountRegistrationCredentialGateTests {
	private let request = AccountRegistrationRequest(account: .currentNickname, email: nil, password: "secret")

	private func session(secured: Bool, validatingChain: Bool = false, prefersTLS: Bool = false) async throws
		-> TestServerSession
	{
		let session = makeRegistrationSession()
		var config = ConnectionConfig()
		config.serverAddress = "irc.example.test"
		config.serverPort = secured ? 6697 : 6667
		config.connectionShouldValidateCertificateChain = validatingChain
		config.connectionPrefersSecuredConnection = prefersTLS
		let connection = Connection(config: config, onSession: session)
		session.socket = connection
		if secured {
			connection.callbackReceiver.didSecureConnection(
				withProtocolType: .TLSv12,
				cipherSuite: tlsCipherSuiteUnknown,
				leafCertificate: Data("registration test certificate".utf8)
			)
			try await Eventually.until("TLS to come up") { connection.isSecured }
		}
		try session.negotiate("draft/account-registration")
		try session.receive(":irc.example.net 001 ada :Welcome")

		return session
	}

	private var registerLines: (TestServerSession) -> [String] {
		{ $0.wireLines.filter { $0.hasPrefix("REGISTER") } }
	}

	@Test("A plaintext connection that wanted TLS refuses and sends nothing")
	func plaintextRefuses() async throws {
		let session = try await session(secured: false, prefersTLS: true)
		let log = AccountRegistrationEventLog()

		session.registerAccount(request, observer: log.observer)

		#expect(log.last == .failed(.credentialsWithheld(.plaintext), serverMessage: nil))
		#expect(registerLines(session).isEmpty)
	}

	@Test("An unchecked certificate asks, and Send sends")
	func uncheckedCertificateSend() async throws {
		let session = try await session(secured: true)
		session.recordedOutput.responseAnswer = .alternate
		let log = AccountRegistrationEventLog()

		session.registerAccount(request, observer: log.observer)
		try await Eventually.until("the answer") { registerLines(session).count == 1 }

		#expect(session.recordedOutput.responseRequests.count == 1)
		#expect(log.last == .started)
	}

	@Test("An unchecked certificate asks, and Don't Send refuses")
	func uncheckedCertificateDecline() async throws {
		let session = try await session(secured: true)
		session.recordedOutput.responseAnswer = .default
		let log = AccountRegistrationEventLog()

		session.registerAccount(request, observer: log.observer)
		try await Eventually.until("the answer") { log.last != nil }

		#expect(log.last == .failed(.credentialsWithheld(.unverifiedCertificate), serverMessage: nil))
		#expect(registerLines(session).isEmpty)
	}

	@Test("The question is asked even after a password was withheld once")
	func explicitRequestAsksAgain() async throws {
		let session = try await session(secured: true)
		session.sessionCredentials.reportedWithheldCredentials = true
		session.recordedOutput.responseAnswer = .alternate

		session.registerAccount(request, observer: AccountRegistrationEventLog().observer)
		try await Eventually.until("the answer") { registerLines(session).count == 1 }
	}

	@Test("A redirected host refuses")
	func redirectedHostRefuses() async throws {
		let session = try await session(secured: true, validatingChain: true)
		session.sessionCredentials.withholdsAccountCredentials = true
		let log = AccountRegistrationEventLog()

		session.registerAccount(request, observer: log.observer)

		#expect(log.last == .failed(.credentialsWithheld(.unconfiguredHost), serverMessage: nil))
		#expect(registerLines(session).isEmpty)
	}

	@Test("A bouncer network refuses")
	func bouncerNetworkRefuses() async throws {
		let session = try await session(secured: true, validatingChain: true)
		session.config.bouncerNetwork = BouncerNetworkBinding(parentIdentifier: "parent", networkIdentifier: "1")
		let log = AccountRegistrationEventLog()

		session.registerAccount(request, observer: log.observer)

		#expect(session.accountRegistrationAvailability == .unavailable(.bouncerNetwork))
		#expect(log.last == .failed(.unsupportedOnBouncerNetwork, serverMessage: nil))
		#expect(registerLines(session).isEmpty)
	}

	@Test("A validated chain sends")
	func validatedChainSends() async throws {
		let session = try await session(secured: true, validatingChain: true)

		session.registerAccount(request, observer: AccountRegistrationEventLog().observer)

		#expect(registerLines(session) == ["REGISTER * * secret"])
	}
}
