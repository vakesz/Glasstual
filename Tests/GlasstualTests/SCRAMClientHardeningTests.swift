// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing

@MainActor
struct SCRAMClientHardeningTests {
	@Test("A duplicate challenge cannot revive a deriving exchange")
	func duplicateChallengeFailsTheSuspendedExchange() async throws {
		let (started, signal) = AsyncStream<Void>.makeStream()
		let (release, resume) = AsyncStream<Void>.makeStream()
		defer { resume.finish(); signal.finish() }
		let client = SCRAMClient(username: "user", password: "pencil",
		                         clientNonce: Self.nonce)
		{ password, salt, iterations in
			signal.yield()
			for await _ in release {
				break
			}
			return await SCRAMClient.pbkdf2Offloaded(password: password, salt: salt, iterations: iterations)
		}
		_ = client.clientFirstMessage
		let challenge = serverFirst(iterations: "4096")
		let first = Task { try await client.clientFinalMessage(forServerFirstMessage: challenge) }
		for await _ in started {
			break
		}
		#expect(client.state == .derivingClientFinal)
		await #expect(throws: NSError.self) {
			try await client.clientFinalMessage(forServerFirstMessage: challenge)
		}
		resume.yield()
		await #expect(throws: NSError.self) { try await first.value }
		#expect(client.state == .failed)
	}

	private static let nonce = "rOprNGfwEbeRWgbNEkqO"
	private static let combinedNonce = "rOprNGfwEbeRWgbNEkqO%hvYDpWUa2RaTCAfuxFIlj)hNlF$k0"
	private static let salt = "W22ZaJ0SNY7soEsUEjb6gQ=="

	private func exampleClient() -> SCRAMClient {
		SCRAMClient(username: "user", password: "pencil", clientNonce: Self.nonce)
	}

	private func serverFirst(iterations: String) -> String {
		"r=\(Self.combinedNonce),s=\(Self.salt),i=\(iterations)"
	}

	/// `i=5000000000` overflows `UInt32` and used to trap inside PBKDF2;
	/// `i=2000000000` was in range but ran for minutes on the main thread.
	@Test(arguments: ["5000000000", "2000000000", "600001", "99999999999999999999"])
	func excessiveIterationCountsAreRejected(_ iterations: String) async {
		let client = exampleClient()
		_ = client.clientFirstMessage

		do {
			_ = try await client.clientFinalMessage(forServerFirstMessage: serverFirst(iterations: iterations))
			Issue.record("Iteration count \(iterations) should have been rejected")
		} catch {
			// A count that does not fit in `Int` fails the earlier
			// malformed-message check instead of the ceiling check.
			let code = (error as NSError).code
			#expect(
				code == SCRAMClientErrorCode.iterationCountTooHigh.rawValue
					|| code == SCRAMClientErrorCode.malformedServerMessage.rawValue
			)
		}
	}

	@Test
	func iterationCountAtTheCeilingIsAccepted() async throws {
		let client = exampleClient()
		_ = client.clientFirstMessage

		_ = try await client.clientFinalMessage(forServerFirstMessage: serverFirst(iterations: "600000"))

		#expect(client.state == .sentClientFinal)
	}

	@Test
	func derivationRejectsIterationCountsOutsideUInt32() {
		#expect(SCRAMClient.pbkdf2(password: "pencil", salt: Data([1, 2, 3]), iterations: -1) == nil)
		#expect(
			SCRAMClient.pbkdf2(password: "pencil", salt: Data([1, 2, 3]), iterations: 5_000_000_000) == nil
		)
	}
}

@MainActor
struct ClientSCRAMMutualAuthenticationTests {
	enum EndAction: CaseIterable {
		case saslReset, capabilityReset, retry, failure, abort, disconnect, termination
	}

	private func receive(_ line: String, on client: Client) throws {
		try client.handleCapabilityOrAuthenticationRequest(#require(Message(line: line, on: client)))
	}

	/// Drives the authentication numeric handler the way `receiveNumericReply`
	/// routes to it.
	private func handleAuthentication(_ message: Message, on client: Client) throws {
		let numeric = try #require(ServerNumeric(rawValue: message.commandNumeric))

		#expect(numeric.group == .authentication)

		client.handleAuthenticationTrackingNumeric(numeric, message: message, shouldPrint: false)
	}

	private func derivingClient() async throws -> (TestClient, AsyncStream<Void>.Continuation) {
		let client = TestClient(
			configDictionary: ["nickname": "user"], nicknamePassword: "pencil",
			fixture: ClientEnvironmentFixture(preferences: ClientPreferences())
		)
		client.socket = Connection(config: ConnectionConfig(), onClient: client)
		client.isConnected = true
		try receive("CAP * LS :sasl=SCRAM-SHA-256,PLAIN", on: client)
		try receive("CAP user ACK :sasl", on: client)
		let (started, signal) = AsyncStream<Void>.makeStream()
		let (release, resume) = AsyncStream<Void>.makeStream()
		let scram = SCRAMClient(username: "user", password: "pencil",
		                        clientNonce: "rOprNGfwEbeRWgbNEkqO")
		{ password, salt, iterations in
			signal.yield()
			for await _ in release {
				break
			}
			return await SCRAMClient.pbkdf2Offloaded(password: password, salt: salt, iterations: iterations)
		}
		_ = scram.clientFirstMessage
		client.sasl.scramClient = scram
		let challenge = Data("r=rOprNGfwEbeRWgbNEkqO%hvYDpWUa2RaTCAfuxFIlj)hNlF$k0,s=W22ZaJ0SNY7soEsUEjb6gQ==,i=4096"
			.utf8).base64EncodedString()
		try receive("AUTHENTICATE \(challenge)", on: client)
		_ = try #require(client.sasl.scramTask)
		for await _ in started {
			break
		}
		#expect(scram.state == .derivingClientFinal)
		return (client, resume)
	}

	@Test("The tracked wire exchange sends the RFC proof and verifies the server")
	func trackedExchangeCompletes() async throws {
		let (client, resume) = try await derivingClient()
		defer { resume.finish() }
		let task = try #require(client.sasl.scramTask)
		resume.yield()
		await task.value
		let proof = "c=biws,r=rOprNGfwEbeRWgbNEkqO%hvYDpWUa2RaTCAfuxFIlj)hNlF$k0,p=dHzbZapWIk4jUhN+Ute9ytag9zjfMHgsqmmiz7AndVQ="
		#expect(client.sentLines.lastObject as? String == "AUTHENTICATE \(Data(proof.utf8).base64EncodedString())")
		#expect(client.sasl.scramTask == nil)
		#expect(client.sasl.scramClient?.state == .sentClientFinal)
		let verified = Data("v=6rriTRBi23WpRR/wtup+mMhUZUn/dB5nLTJRsjl95G4=".utf8).base64EncodedString()
		try receive("AUTHENTICATE \(verified)", on: client)
		#expect(client.sasl.scramClient?.state == .authenticated)
		let result = try #require(Message(line: ":server 903 user :Authenticated", on: client))
		try handleAuthentication(result, on: client)
		#expect(client.isCapabilityEnabled(.isIdentifiedWithSASL))
	}

	@Test("Session endings cancel suspended SCRAM without sending its result", arguments: EndAction.allCases)
	func sessionEndCancelsDerivation(_ action: EndAction) async throws {
		let (client, resume) = try await derivingClient()
		let task = try #require(client.sasl.scramTask)
		defer { resume.finish() }
		switch action {
		case .saslReset: client.resetSASLNegotiation()
		case .capabilityReset: client.resetCapabilityNegotiation()
		case .retry: #expect(client.retrySASLNegotiation(withMechanisms: ["PLAIN"]))
		case .failure:
			let message = try #require(Message(line: ":server 902 user :Locked", on: client))
			try handleAuthentication(message, on: client)
		case .abort: try receive("AUTHENTICATE !invalid!", on: client)
		case .disconnect: client.disconnect()
		case .termination: client.isTerminating = true
		}
		#expect(task.isCancelled)
		#expect(client.sasl.scramTask == nil)
		let sent = client.sentLines.compactMap { $0 as? String }
		resume.yield()
		await task.value
		#expect(client.sentLines.compactMap { $0 as? String } == sent)
	}

	@Test("A suspended SCRAM result cannot reach a replacement connection")
	func replacementConnectionRejectsOldResult() async throws {
		let (client, resume) = try await derivingClient()
		let task = try #require(client.sasl.scramTask)
		defer { resume.finish() }
		client.socket = Connection(config: ConnectionConfig(), onClient: client)
		let sent = client.sentLines.compactMap { $0 as? String }
		resume.yield()
		await task.value
		#expect(client.sentLines.compactMap { $0 as? String } == sent)
		#expect(client.sasl.scramTask == nil)
	}

	@Test("A retired exchange cannot send or clear a replacement exchange's task")
	func replacementExchangeKeepsItsTask() async throws {
		let (client, resume) = try await derivingClient()
		let retired = try #require(client.sasl.scramTask)
		defer { resume.finish() }
		let replacement = SCRAMClient(username: "user", password: "pencil", clientNonce: "replacement")
		client.sasl.scramClient = replacement
		let pending = Task<Void, Never> { try? await Task.sleep(for: .seconds(60)) }
		client.sasl.scramTask = pending
		defer { client.resetSASLNegotiation() }
		let sent = client.sentLines.compactMap { $0 as? String }
		resume.yield()
		await retired.value
		#expect(retired.isCancelled)
		#expect(client.sasl.scramClient === replacement)
		#expect(client.sasl.scramTask != nil)
		#expect(pending.isCancelled == false)
		#expect(client.sentLines.compactMap { $0 as? String } == sent)
	}

	@Test("A second wire challenge aborts rather than launching another derivation")
	func duplicateWireChallengeAborts() async throws {
		let (client, resume) = try await derivingClient()
		let task = try #require(client.sasl.scramTask)
		defer { resume.finish() }
		let challenge = Data("r=nonce-server,s=c2FsdA==,i=4096".utf8).base64EncodedString()
		try receive("AUTHENTICATE \(challenge)", on: client)
		#expect(task.isCancelled)
		#expect(client.sasl.scramTask == nil)
		#expect(client.sentLines.contains("AUTHENTICATE *"))
		let sent = client.sentLines.compactMap { $0 as? String }
		resume.yield()
		await task.value
		#expect(client.sentLines.compactMap { $0 as? String } == sent)
	}

	/// A client mid-exchange: the check only guards a SASL negotiation in flight.
	private func client(mechanism: String?, scram: SCRAMClient?) -> TestClient {
		let client = TestClient()
		client.enableCapability(.isInSASLNegotiation)
		client.sasl.mechanism = mechanism
		client.sasl.scramClient = scram
		return client
	}

	@Test
	func nonSCRAMMechanismsDoNotRequireAServerSignature() {
		#expect(client(mechanism: nil, scram: nil).scramMutualAuthenticationIsSatisfied())
		#expect(client(mechanism: "PLAIN", scram: nil).scramMutualAuthenticationIsSatisfied())
		#expect(client(mechanism: "EXTERNAL", scram: nil).scramMutualAuthenticationIsSatisfied())
	}

	/// A server that skips `server-final-message` and jumps straight to
	/// 900/903 has proved nothing, so success must not be believed.
	@Test
	func scramWithoutAVerifiedServerFinalMessageIsNotSatisfied() {
		let scram = SCRAMClient(username: "user", password: "pencil")
		let client = client(mechanism: SCRAMClient.mechanismName, scram: scram)

		#expect(client.scramMutualAuthenticationIsSatisfied() == false)

		_ = scram.clientFirstMessage

		#expect(client.scramMutualAuthenticationIsSatisfied() == false)
	}

	@Test
	func scramWithAVerifiedServerFinalMessageIsSatisfied() async throws {
		let scram = SCRAMClient(username: "user", password: "pencil", clientNonce: "rOprNGfwEbeRWgbNEkqO")
		_ = scram.clientFirstMessage
		_ = try await scram.clientFinalMessage(
			forServerFirstMessage:
			"r=rOprNGfwEbeRWgbNEkqO%hvYDpWUa2RaTCAfuxFIlj)hNlF$k0,s=W22ZaJ0SNY7soEsUEjb6gQ==,i=4096"
		)
		try scram.verifyServerFinalMessage("v=6rriTRBi23WpRR/wtup+mMhUZUn/dB5nLTJRsjl95G4=")

		let client = client(mechanism: SCRAMClient.mechanismName, scram: scram)

		#expect(client.scramMutualAuthenticationIsSatisfied())
	}
}
