// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
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
	private func securedSession(validatingChain: Bool) async throws -> TestServerSession {
		let session = TestServerSession(configDictionary: ["usesSASL": true], nicknamePassword: "secret")
		session.setConnectionTransportForTesting(.connected)
		var config = ConnectionConfig()
		config.serverAddress = "irc.example.test"
		config.serverPort = 6697
		config.connectionShouldValidateCertificateChain = validatingChain
		let connection = Connection(config: config, onSession: session)
		session.socket = connection
		connection.callbackReceiver.didSecureConnection(withProtocolType: .TLSv12, cipherSuite: tlsCipherSuiteUnknown)
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

		session.credentialConsent = CredentialConsent(host: "IRC.example.test", port: 6697)
		#expect(session.permitsCredentialsInClear)

		session.credentialConsent = CredentialConsent(host: "irc.example.test", port: 6667)
		#expect(session.permitsCredentialsInClear == false)
		session.credentialConsent = CredentialConsent(host: "irc.other.test", port: 6697)
		#expect(session.permitsCredentialsInClear == false)
	}

	@Test("PLAIN stays on offer while the question is open, and SCRAM is preferred over it")
	func plainWaitsForTheQuestion() async throws {
		let session = try await securedSession(validatingChain: false)

		#expect(session.selectSASLMechanism(fromOffered: ["PLAIN"]))
		#expect(session.sasl.mechanism == "PLAIN")
		#expect(session.selectSASLMechanism(fromOffered: ["PLAIN", SCRAMClient.mechanismName]))
		#expect(session.sasl.mechanism == SCRAMClient.mechanismName)

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

		#expect(session.credentialConsent == CredentialConsent(host: "irc.example.test", port: 6697))
		#expect((session.sentLines as NSArray).compactMap { $0 as? String }.contains { $0.contains("IDENTIFY secret") })
	}
}
