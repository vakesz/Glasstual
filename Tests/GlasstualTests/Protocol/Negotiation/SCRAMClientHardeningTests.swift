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
		let session = SCRAMClient(username: "user", password: "pencil",
		                          clientNonce: Self.nonce)
		{ password, salt, iterations in
			signal.yield()
			for await _ in release {
				break
			}
			return await SCRAMClient.pbkdf2Offloaded(password: password, salt: salt, iterations: iterations)
		}
		_ = session.clientFirstMessage
		let challenge = serverFirst(iterations: "4096")
		let first = Task { try await session.clientFinalMessage(forServerFirstMessage: challenge) }
		for await _ in started {
			break
		}
		#expect(session.state == .derivingClientFinal)
		await #expect(throws: NSError.self) {
			try await session.clientFinalMessage(forServerFirstMessage: challenge)
		}
		resume.yield()
		await #expect(throws: NSError.self) { try await first.value }
		#expect(session.state == .failed)
	}

	private static let nonce = "rOprNGfwEbeRWgbNEkqO"
	private static let combinedNonce = "rOprNGfwEbeRWgbNEkqO%hvYDpWUa2RaTCAfuxFIlj)hNlF$k0"
	private static let salt = "W22ZaJ0SNY7soEsUEjb6gQ=="

	private func exampleSession() -> SCRAMClient {
		SCRAMClient(username: "user", password: "pencil", clientNonce: Self.nonce)
	}

	private func serverFirst(iterations: String) -> String {
		"r=\(Self.combinedNonce),s=\(Self.salt),i=\(iterations)"
	}

	/// `i=5000000000` overflows `UInt32` and used to trap inside PBKDF2;
	/// `i=2000000000` was in range but ran for minutes on the main thread.
	@Test(arguments: ["5000000000", "2000000000", "600001", "99999999999999999999"])
	func excessiveIterationCountsAreRejected(_ iterations: String) async {
		let session = exampleSession()
		_ = session.clientFirstMessage

		do {
			_ = try await session.clientFinalMessage(forServerFirstMessage: serverFirst(iterations: iterations))
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
		let session = exampleSession()
		_ = session.clientFirstMessage

		_ = try await session.clientFinalMessage(forServerFirstMessage: serverFirst(iterations: "600000"))

		#expect(session.state == .sentClientFinal)
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
struct ServerSessionSCRAMMutualAuthenticationTests {
	enum EndAction: CaseIterable {
		case saslReset, capabilityReset, retry, failure, abort, disconnect, termination
	}

	private func receive(_ line: String, on session: ServerSession) throws {
		try session.handleCapabilityOrAuthenticationRequest(#require(Message(line: line, on: session)))
	}

	/// Drives the authentication numeric handler the way `receiveNumericReply`
	/// routes to it.
	private func handleAuthentication(_ message: Message, on session: ServerSession) throws {
		let numeric = try #require(ServerNumeric(rawValue: message.commandNumeric))

		#expect(numeric.group == .authentication)

		session.handleAuthenticationTrackingNumeric(numeric, message: message, shouldPrint: false)
	}

	private func derivingClient() async throws -> (TestServerSession, AsyncStream<Void>.Continuation) {
		let session = TestServerSession(
			configDictionary: ["nickname": "user"], nicknamePassword: "pencil",
			fixture: ChatEnvironmentFixture(settings: ChatSettings())
		)
		session.socket = Connection(config: ConnectionConfig(), onSession: session)
		session.isConnected = true
		try receive("CAP * LS :sasl=SCRAM-SHA-256,PLAIN", on: session)
		try receive("CAP user ACK :sasl", on: session)
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
		session.sasl.scramSession = scram
		let challenge = Data("r=rOprNGfwEbeRWgbNEkqO%hvYDpWUa2RaTCAfuxFIlj)hNlF$k0,s=W22ZaJ0SNY7soEsUEjb6gQ==,i=4096"
			.utf8).base64EncodedString()
		try receive("AUTHENTICATE \(challenge)", on: session)
		_ = try #require(session.sasl.scramTask)
		for await _ in started {
			break
		}
		#expect(scram.state == .derivingClientFinal)
		return (session, resume)
	}

	@Test("The tracked wire exchange sends the RFC proof and verifies the server")
	func trackedExchangeCompletes() async throws {
		let (session, resume) = try await derivingClient()
		defer { resume.finish() }
		let task = try #require(session.sasl.scramTask)
		resume.yield()
		await task.value
		let proof = "c=biws,r=rOprNGfwEbeRWgbNEkqO%hvYDpWUa2RaTCAfuxFIlj)hNlF$k0,p=dHzbZapWIk4jUhN+Ute9ytag9zjfMHgsqmmiz7AndVQ="
		#expect(session.sentLines.lastObject as? String == "AUTHENTICATE \(Data(proof.utf8).base64EncodedString())")
		#expect(session.sasl.scramTask == nil)
		#expect(session.sasl.scramSession?.state == .sentClientFinal)
		let verified = Data("v=6rriTRBi23WpRR/wtup+mMhUZUn/dB5nLTJRsjl95G4=".utf8).base64EncodedString()
		try receive("AUTHENTICATE \(verified)", on: session)
		#expect(session.sasl.scramSession?.state == .authenticated)
		let result = try #require(Message(line: ":server 903 user :Authenticated", on: session))
		try handleAuthentication(result, on: session)
		#expect(session.isCapabilityEnabled(.isIdentifiedWithSASL))
	}

	@Test("Session endings cancel suspended SCRAM without sending its result", arguments: EndAction.allCases)
	func sessionEndCancelsDerivation(_ action: EndAction) async throws {
		let (session, resume) = try await derivingClient()
		let task = try #require(session.sasl.scramTask)
		defer { resume.finish() }
		switch action {
		case .saslReset: session.resetSASLNegotiation()
		case .capabilityReset: session.resetCapabilityNegotiation()
		case .retry: #expect(session.retrySASLNegotiation(withMechanisms: ["PLAIN"]))
		case .failure:
			let message = try #require(Message(line: ":server 902 user :Locked", on: session))
			try handleAuthentication(message, on: session)
		case .abort: try receive("AUTHENTICATE !invalid!", on: session)
		case .disconnect: session.disconnect()
		case .termination: session.isTerminating = true
		}
		#expect(task.isCancelled)
		#expect(session.sasl.scramTask == nil)
		let sent = session.sentLines.compactMap { $0 as? String }
		resume.yield()
		await task.value
		#expect(session.sentLines.compactMap { $0 as? String } == sent)
	}

	@Test("A suspended SCRAM result cannot reach a replacement connection")
	func replacementConnectionRejectsOldResult() async throws {
		let (session, resume) = try await derivingClient()
		let task = try #require(session.sasl.scramTask)
		defer { resume.finish() }
		session.socket = Connection(config: ConnectionConfig(), onSession: session)
		let sent = session.sentLines.compactMap { $0 as? String }
		resume.yield()
		await task.value
		#expect(session.sentLines.compactMap { $0 as? String } == sent)
		#expect(session.sasl.scramTask == nil)
	}

	@Test("A retired exchange cannot send or clear a replacement exchange's task")
	func replacementExchangeKeepsItsTask() async throws {
		let (session, resume) = try await derivingClient()
		let retired = try #require(session.sasl.scramTask)
		defer { resume.finish() }
		let replacement = SCRAMClient(username: "user", password: "pencil", clientNonce: "replacement")
		session.sasl.scramSession = replacement
		let pending = Task<Void, Never> { try? await Task.sleep(for: .seconds(60)) }
		session.sasl.scramTask = pending
		defer { session.resetSASLNegotiation() }
		let sent = session.sentLines.compactMap { $0 as? String }
		resume.yield()
		await retired.value
		#expect(retired.isCancelled)
		#expect(session.sasl.scramSession === replacement)
		#expect(session.sasl.scramTask != nil)
		#expect(pending.isCancelled == false)
		#expect(session.sentLines.compactMap { $0 as? String } == sent)
	}

	@Test("A second wire challenge aborts rather than launching another derivation")
	func duplicateWireChallengeAborts() async throws {
		let (session, resume) = try await derivingClient()
		let task = try #require(session.sasl.scramTask)
		defer { resume.finish() }
		let challenge = Data("r=nonce-server,s=c2FsdA==,i=4096".utf8).base64EncodedString()
		try receive("AUTHENTICATE \(challenge)", on: session)
		#expect(task.isCancelled)
		#expect(session.sasl.scramTask == nil)
		#expect(session.sentLines.contains("AUTHENTICATE *"))
		let sent = session.sentLines.compactMap { $0 as? String }
		resume.yield()
		await task.value
		#expect(session.sentLines.compactMap { $0 as? String } == sent)
	}

	/// A session mid-exchange: the check only guards a SASL negotiation in flight.
	private func session(mechanism: String?, scram: SCRAMClient?) -> TestServerSession {
		let session = TestServerSession()
		session.enableCapability(.isInSASLNegotiation)
		session.sasl.mechanism = mechanism
		session.sasl.scramSession = scram
		return session
	}

	@Test
	func nonSCRAMMechanismsDoNotRequireAServerSignature() {
		#expect(session(mechanism: nil, scram: nil).scramMutualAuthenticationIsSatisfied())
		#expect(session(mechanism: "PLAIN", scram: nil).scramMutualAuthenticationIsSatisfied())
		#expect(session(mechanism: "EXTERNAL", scram: nil).scramMutualAuthenticationIsSatisfied())
	}

	/// A server that skips `server-final-message` and jumps straight to
	/// 900/903 has proved nothing, so success must not be believed.
	@Test
	func scramWithoutAVerifiedServerFinalMessageIsNotSatisfied() {
		let scram = SCRAMClient(username: "user", password: "pencil")
		let session = session(mechanism: SCRAMClient.mechanismName, scram: scram)

		#expect(session.scramMutualAuthenticationIsSatisfied() == false)

		_ = scram.clientFirstMessage

		#expect(session.scramMutualAuthenticationIsSatisfied() == false)
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

		let session = session(mechanism: SCRAMClient.mechanismName, scram: scram)

		#expect(session.scramMutualAuthenticationIsSatisfied())
	}
}
