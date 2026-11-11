// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import CryptoKit
import Foundation
@testable import Glasstual
import Testing

/** A password SASL `PLAIN` or a NickServ `IDENTIFY` would send in clear needs a
 connection that can vouch for the server: a chain the system accepted, one the
 user chose to continue with, or a host the user allowed. SCRAM and EXTERNAL
 never send the password, so they are not held back. */
@MainActor
@Suite("Credential consent for unverified certificates", .timeLimit(.minutes(1)))
struct ServerSessionCredentialConsentTests {
	/// Stand-ins for the DER of two server certificates; only their digests are compared.
	private static let certificate = Data("certificate the user saw".utf8)
	private static let otherCertificate = Data("certificate an impostor presents".utf8)

	private static func fingerprint(_ certificate: Data) -> Data {
		Data(SHA256.hash(data: certificate))
	}

	private static func consent(_ host: String, _ port: UInt16, certificate: Data? = certificate) -> CredentialConsent {
		CredentialConsent(host: host, port: port, certificateFingerprint: certificate.map(fingerprint))
	}

	private func securedSession(validatingChain: Bool) async throws -> TestServerSession {
		let session = TestServerSession(configDictionary: ["usesSASL": true], nicknamePassword: "secret")
		session.setConnectionTransportForTesting(.connected)
		var config = ConnectionConfig()
		config.serverAddress = "irc.example.test"
		config.serverPort = 6697
		config.connectionShouldValidateCertificateChain = validatingChain
		let connection = Connection(config: config, onSession: session)
		session.socket = connection
		connection.callbackReceiver.didSecureConnection(
			withProtocolType: .TLSv12,
			cipherSuite: tlsCipherSuiteUnknown,
			leafCertificate: Self.certificate
		)
		try await Eventually.until("TLS to come up") { connection.isSecured }
		return session
	}

	private func message(_ line: String, on session: ServerSession) throws -> Message {
		try #require(Message(line: line, on: session))
	}

	private func capabilityCommands(of session: TestServerSession) -> [String] {
		(session.sentCapabilityCommands as NSArray).compactMap { $0 as? String }
	}

	private func printedBodies(of session: TestServerSession) -> [String] {
		(session.printedLines as NSArray).compactMap { ($0 as? [String: Any])?["messageBody"] as? String }
	}

	@Test("A validated chain carries the password")
	func validatedChainPermitsCredentials() async throws {
		let session = try await securedSession(validatingChain: true)

		#expect(session.permitsCredentialsInClear)
		#expect(session.mayAskToSendCredentials == false)
	}

	@Test("An unchecked chain holds the password until the user allows the host and port")
	func uncheckedChainNeedsConsent() async throws {
		let session = try await securedSession(validatingChain: false)

		#expect(session.permitsCredentialsInClear == false)
		#expect(session.mayAskToSendCredentials)

		session.credentialConsent = Self.consent("IRC.example.test", 6697)
		#expect(session.permitsCredentialsInClear)

		session.credentialConsent = Self.consent("irc.example.test", 6667)
		#expect(session.permitsCredentialsInClear == false)
		session.credentialConsent = Self.consent("irc.other.test", 6697)
		#expect(session.permitsCredentialsInClear == false)
	}

	/** SASL `PLAIN` and a NickServ `IDENTIFY` read `permitsCredentialsInClear`,
	 so an impostor at the same address with its own certificate gets neither. */
	@Test("A consent covers the host only while it presents the certificate the user saw")
	func consentIsBoundToTheCertificate() async throws {
		let session = try await securedSession(validatingChain: false)

		session.credentialConsent = Self.consent("irc.example.test", 6697, certificate: Self.otherCertificate)
		#expect(session.permitsCredentialsInClear == false)
		#expect(session.mayAskToSendCredentials)

		session.credentialConsent = Self.consent("irc.example.test", 6697, certificate: nil)
		#expect(session.permitsCredentialsInClear == false, "A consent with no certificate is not honoured silently")
		#expect(session.mayAskToSendCredentials)
	}

	@Test("PLAIN stays on offer while the question is open, and SCRAM is preferred over it")
	func plainWaitsForTheQuestion() async throws {
		let session = try await securedSession(validatingChain: false)

		#expect(session.selectSASLMechanism(fromOffered: ["PLAIN"]))
		#expect(session.sasl.mechanism == .plain)
		#expect(session.selectSASLMechanism(fromOffered: ["PLAIN", "SCRAM-SHA-256"]))
		#expect(session.sasl.mechanism == .scramSHA256)

		session.sessionCredentials.reportedWithheldCredentials = true

		#expect(session.selectSASLMechanism(fromOffered: ["PLAIN"]) == false)
	}

	@Test("Offering SCRAM asks nothing and says nothing")
	func scramIsNotHeldBack() async throws {
		let session = try await securedSession(validatingChain: false)

		try session.handleCapabilityOrAuthenticationRequest(message(
			":irc.example.net CAP * LS :sasl=SCRAM-SHA-256", on: session
		))

		#expect(capabilityCommands(of: session) == ["REQ sasl"])
		#expect(session.recordedOutput.responseRequests.isEmpty)
		#expect(printedBodies(of: session).contains(ConnectionSafetyStrings.Credentials.withheldUnverifiedCertificate) == false)
	}

	@Test("The question keeps the password back by default and offers no way to stop asking")
	func alertIsSafeByDefault() {
		let alert = ServerSession.credentialConsentAlert(host: "irc.example.test")

		#expect(alert.defaultButton == ConnectionSafetyStrings.Credentials.dontSend)
		#expect(alert.alternateButton == ConnectionSafetyStrings.Credentials.send)
		#expect(alert.cancelButton == .default)
		#expect(alert.suppressionKey == nil)
		#expect(alert.body.contains("irc.example.test"))
	}

	@Test("Declining keeps the password back and records nothing")
	func decliningSendsNothing() async throws {
		let session = try await securedSession(validatingChain: false)

		session.reportWithheldCredentials()
		try await Eventually.until("the question") { session.recordedOutput.responseRequests.count == 1 }
		await Task.yield()

		#expect(session.credentialConsent == nil)
		#expect(session.permitsCredentialsInClear == false)
		#expect(printedBodies(of: session).contains(ConnectionSafetyStrings.Credentials.withheldUnverifiedCertificate))
		session.reportWithheldCredentials()
		#expect(session.recordedOutput.responseRequests.count == 1)
	}

	@Test("Allowing records the host and port and identifies with services")
	func allowingSendsTheIdentification() async throws {
		let session = try await securedSession(validatingChain: false)
		session.recordedOutput.responseAnswer = .alternate

		session.reportWithheldCredentials()
		try await Eventually.until("the consent") { session.hasCredentialConsent }

		#expect(session.credentialConsent == Self.consent("irc.example.test", 6697))
		#expect((session.sentLines as NSArray).compactMap { $0 as? String }.contains { $0.contains("IDENTIFY secret") })
	}

	// MARK: - Server password

	/// A session with a server password and a connection that has reported it
	/// connected, but has not finished any TLS handshake.
	private func registeringSession(
		endpointWantsTLS: Bool,
		validatingChain: Bool = true,
		serverWantsTLS: Bool = false
	) async throws -> (TestServerSession, Connection) {
		let session = TestServerSession(configDictionary: ["nickname": "Guest"], nicknamePassword: nil)
		session.forwardsProcessedMessages = true
		session.setConnectionTransportForTesting(.connected)
		session.endpoints.current = ServerEndpoint(
			serverAddress: "bouncer.example.test",
			prefersSecuredConnection: serverWantsTLS,
			pendingServerPassword: .set("bouncer-secret")
		)
		var config = ConnectionConfig()
		config.serverAddress = "bouncer.example.test"
		config.serverPort = 6697
		config.connectionPrefersSecuredConnection = endpointWantsTLS
		config.connectionShouldValidateCertificateChain = validatingChain
		let connection = Connection(config: config, onSession: session)
		session.socket = connection
		connection.callbackReceiver.didConnect(toHost: config.serverAddress)
		try await Eventually.until("the connection") { connection.isConnected }
		return (session, connection)
	}

	private func secure(_ connection: Connection, presenting certificate: Data? = certificate) async throws {
		connection.callbackReceiver.didSecureConnection(
			withProtocolType: .TLSv13,
			cipherSuite: tlsCipherSuiteUnknown,
			leafCertificate: certificate
		)
		try await Eventually.until("TLS to come up") { connection.isSecured }
	}

	private func registrationCommands(of session: TestServerSession) -> [String] {
		(session.sentLines as NSArray).compactMap { $0 as? String }.compactMap { line in
			let command = line.prefix { $0 != " " }
			return ["PASS", "NICK", "USER"].contains(String(command)) ? String(command) : nil
		}
	}

	private func passLines(of session: TestServerSession) -> [String] {
		(session.sentLines as NSArray).compactMap { $0 as? String }.filter { $0.hasPrefix("PASS ") }
	}

	@Test("Registration on a TLS endpoint waits for the handshake")
	func registrationWaitsForTLS() async throws {
		let (session, connection) = try await registeringSession(endpointWantsTLS: true)
		defer { session.stopAllTimers() }

		#expect(registrationCommands(of: session).isEmpty)
		#expect(capabilityCommands(of: session).isEmpty)
		#expect(session.registration.gate == .awaitingTLS)

		try await secure(connection)

		#expect(capabilityCommands(of: session) == ["LS 302"])
		#expect(registrationCommands(of: session) == ["PASS", "NICK", "USER"])
		try #expect(passLines(of: session) == [SendingMessage.string(command: .pass, arguments: ["bouncer-secret"])])
		#expect(session.recordedOutput.responseRequests.isEmpty)
		#expect(session.registration.gate == .sent)
	}

	@Test("An unchecked chain asks before PASS and holds NICK and USER")
	func uncheckedChainAsksBeforePassword() async throws {
		let (session, connection) = try await registeringSession(endpointWantsTLS: true, validatingChain: false)
		defer { session.stopAllTimers() }
		session.recordedOutput.responseAnswer = .alternate

		try await secure(connection)
		#expect(session.registration.gate == .awaitingCredentialConsent || session.registration.gate == .sent)
		try await Eventually.until("the registration") { session.registration.gate == .sent }

		#expect(session.recordedOutput.responseRequests.count == 1)
		#expect(registrationCommands(of: session) == ["PASS", "NICK", "USER"])
		try #expect(passLines(of: session) == [SendingMessage.string(command: .pass, arguments: ["bouncer-secret"])])
		#expect(session.credentialConsent == Self.consent("bouncer.example.test", 6697))
		#expect(session.permitsCredentialsInClear, "The same answer clears SASL PLAIN, so it is not asked again")
	}

	@Test("Declining the question registers without PASS")
	func decliningRegistersWithoutPassword() async throws {
		let (session, connection) = try await registeringSession(endpointWantsTLS: true, validatingChain: false)
		defer { session.stopAllTimers() }

		try await secure(connection)
		try await Eventually.until("the registration") { session.registration.gate == .sent }

		#expect(session.recordedOutput.responseRequests.count == 1)
		#expect(registrationCommands(of: session) == ["NICK", "USER"])
		#expect(session.credentialConsent == nil)
		#expect(printedBodies(of: session).contains(ConnectionSafetyStrings.Credentials.withheldUnverifiedCertificate))

		session.reportWithheldCredentials()
		#expect(session.recordedOutput.responseRequests.count == 1)
	}

	@Test("A host already allowed sends PASS without asking")
	func allowedHostSendsPassword() async throws {
		let (session, connection) = try await registeringSession(endpointWantsTLS: true, validatingChain: false)
		defer { session.stopAllTimers() }
		session.credentialConsent = Self.consent("bouncer.example.test", 6697)

		try await secure(connection)

		#expect(session.recordedOutput.responseRequests.isEmpty)
		#expect(registrationCommands(of: session) == ["PASS", "NICK", "USER"])
		try #expect(passLines(of: session) == [SendingMessage.string(command: .pass, arguments: ["bouncer-secret"])])
	}

	/** The reconnect the consent outlives: same host and port, another
	 certificate. Nothing is written until the user answers, and the question
	 says the certificate is not the one they allowed. */
	@Test("A host that now presents another certificate is asked about again before PASS")
	func changedCertificateAsksAgain() async throws {
		let (session, connection) = try await registeringSession(endpointWantsTLS: true, validatingChain: false)
		defer { session.stopAllTimers() }
		session.credentialConsent = Self.consent("bouncer.example.test", 6697)

		try await secure(connection, presenting: Self.otherCertificate)
		try await Eventually.until("the registration") { session.registration.gate == .sent }

		let request = try #require(session.recordedOutput.responseRequests.first)
		#expect(session.recordedOutput.responseRequests.count == 1)
		#expect(request.body == ConnectionSafetyStrings.Credentials.changedCertificateBody(host: "bouncer.example.test"))
		#expect(passLines(of: session).isEmpty)
		#expect(registrationCommands(of: session) == ["NICK", "USER"])
		#expect(session.permitsCredentialsInClear == false)
	}

	@Test("Allowing a changed certificate records it in place of the old one")
	func allowingChangedCertificateRecordsIt() async throws {
		let (session, connection) = try await registeringSession(endpointWantsTLS: true, validatingChain: false)
		defer { session.stopAllTimers() }
		session.credentialConsent = Self.consent("bouncer.example.test", 6697)
		session.recordedOutput.responseAnswer = .alternate

		try await secure(connection, presenting: Self.otherCertificate)
		try await Eventually.until("the registration") { session.registration.gate == .sent }

		try #expect(passLines(of: session) == [SendingMessage.string(command: .pass, arguments: ["bouncer-secret"])])
		#expect(session.credentialConsent == Self.consent("bouncer.example.test", 6697, certificate: Self.otherCertificate))
	}

	@Test("A connection that showed no certificate is asked about every time")
	func missingCertificateAsks() async throws {
		let (session, connection) = try await registeringSession(endpointWantsTLS: true, validatingChain: false)
		defer { session.stopAllTimers() }
		session.credentialConsent = Self.consent("bouncer.example.test", 6697, certificate: nil)

		try await secure(connection, presenting: nil)
		try await Eventually.until("the registration") { session.registration.gate == .sent }

		#expect(session.recordedOutput.responseRequests.count == 1)
		#expect(passLines(of: session).isEmpty)
	}

	@Test("Plaintext where nothing asked for TLS sends PASS at connect")
	func plaintextSendsPassword() async throws {
		let (session, _) = try await registeringSession(endpointWantsTLS: false)
		defer { session.stopAllTimers() }

		#expect(session.recordedOutput.responseRequests.isEmpty)
		#expect(capabilityCommands(of: session) == ["LS 302"])
		#expect(registrationCommands(of: session) == ["PASS", "NICK", "USER"])
		try #expect(passLines(of: session) == [SendingMessage.string(command: .pass, arguments: ["bouncer-secret"])])
	}

	@Test("Plaintext where the server entry wanted TLS withholds PASS and still registers")
	func plaintextWithheldWhenTLSWasWanted() async throws {
		let (session, _) = try await registeringSession(endpointWantsTLS: false, serverWantsTLS: true)
		defer { session.stopAllTimers() }

		#expect(session.recordedOutput.responseRequests.isEmpty)
		#expect(registrationCommands(of: session) == ["NICK", "USER"])
		#expect(printedBodies(of: session).contains(ConnectionSafetyStrings.Credentials.withheldOverPlaintext))
	}
}
