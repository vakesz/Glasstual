/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 *
 *  * Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 *  * Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 *  * Neither the name of Textual, "Codeux Software, LLC", nor the
 *    names of its contributors may be used to endorse or promote products
 *    derived from this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED. IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
 * FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
 * OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
 * LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
 * OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
 * SUCH DAMAGE.
 *
 *********************************************************************** */

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

	/// The derivation the client actually runs has to produce the RFC 7677
	/// vector when the exchange is driven with the vector's nonce and salt.
	@Test
	func offloadedDerivationMatchesTheRFC7677Vector() async throws {
		let client = exampleClient()
		_ = client.clientFirstMessage

		let clientFinal = try await client.clientFinalMessage(
			forServerFirstMessage: serverFirst(iterations: "4096")
		)

		#expect(
			clientFinal
				== "c=biws,r=\(Self.combinedNonce),p=dHzbZapWIk4jUhN+Ute9ytag9zjfMHgsqmmiz7AndVQ="
		)
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
struct IRCClientSCRAMMutualAuthenticationTests {
	enum EndAction: CaseIterable {
		case saslReset, capabilityReset, retry, failure, abort, disconnect, termination
	}

	private func receive(_ line: String, on client: IRCClient) throws {
		try client.handleCapabilityOrAuthenticationRequest(#require(Message(line: line, on: client)))
	}

	private func derivingClient() async throws -> (GLTTestClient, AsyncStream<Void>.Continuation) {
		let client = GLTTestClient(
			configDictionary: ["nickname": "user"], nicknamePassword: "pencil",
			fixture: GLTClientEnvironmentFixture(preferences: ClientPreferences())
		)
		client.socket = Connection(config: IRCConnectionConfig(), onClient: client)
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
		client.saslScramClient = scram
		let challenge = Data("r=rOprNGfwEbeRWgbNEkqO%hvYDpWUa2RaTCAfuxFIlj)hNlF$k0,s=W22ZaJ0SNY7soEsUEjb6gQ==,i=4096"
			.utf8).base64EncodedString()
		try receive("AUTHENTICATE \(challenge)", on: client)
		_ = try #require(client.saslScramTask)
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
		let task = try #require(client.saslScramTask)
		resume.yield()
		await task.value
		let proof = "c=biws,r=rOprNGfwEbeRWgbNEkqO%hvYDpWUa2RaTCAfuxFIlj)hNlF$k0,p=dHzbZapWIk4jUhN+Ute9ytag9zjfMHgsqmmiz7AndVQ="
		#expect(client.sentLines.lastObject as? String == "AUTHENTICATE \(Data(proof.utf8).base64EncodedString())")
		#expect(client.saslScramTask == nil)
		#expect(client.saslScramClient?.state == .sentClientFinal)
		let verified = Data("v=6rriTRBi23WpRR/wtup+mMhUZUn/dB5nLTJRsjl95G4=".utf8).base64EncodedString()
		try receive("AUTHENTICATE \(verified)", on: client)
		#expect(client.saslScramClient?.state == .authenticated)
		let result = try #require(Message(line: ":server 903 user :Authenticated", on: client))
		#expect(client.handleTrackingNumeric(result.commandNumeric, message: result, shouldPrint: false))
		#expect(client.isCapabilityEnabled(.isIdentifiedWithSASL))
	}

	@Test("Session endings cancel suspended SCRAM without sending its result", arguments: EndAction.allCases)
	func sessionEndCancelsDerivation(_ action: EndAction) async throws {
		let (client, resume) = try await derivingClient()
		let task = try #require(client.saslScramTask)
		defer { resume.finish() }
		switch action {
		case .saslReset: client.resetSASLNegotiation()
		case .capabilityReset: client.resetCapabilityNegotiation()
		case .retry: #expect(client.retrySASLNegotiation(withMechanisms: ["PLAIN"]))
		case .failure:
			let message = try #require(Message(line: ":server 902 user :Locked", on: client))
			#expect(client.handleTrackingNumeric(message.commandNumeric, message: message, shouldPrint: false))
		case .abort: try receive("AUTHENTICATE !invalid!", on: client)
		case .disconnect: client.disconnect()
		case .termination: client.isTerminating = true
		}
		#expect(task.isCancelled)
		#expect(client.saslScramTask == nil)
		let sent = client.sentLines.compactMap { $0 as? String }
		resume.yield()
		await task.value
		#expect(client.sentLines.compactMap { $0 as? String } == sent)
	}

	@Test("A suspended SCRAM result cannot reach a replacement connection")
	func replacementConnectionRejectsOldResult() async throws {
		let (client, resume) = try await derivingClient()
		let task = try #require(client.saslScramTask)
		defer { resume.finish() }
		client.socket = Connection(config: IRCConnectionConfig(), onClient: client)
		let sent = client.sentLines.compactMap { $0 as? String }
		resume.yield()
		await task.value
		#expect(client.sentLines.compactMap { $0 as? String } == sent)
		#expect(client.saslScramTask == nil)
	}

	@Test("A retired exchange cannot send or clear a replacement exchange's task")
	func replacementExchangeKeepsItsTask() async throws {
		let (client, resume) = try await derivingClient()
		let retired = try #require(client.saslScramTask)
		defer { resume.finish() }
		let replacement = SCRAMClient(username: "user", password: "pencil", clientNonce: "replacement")
		client.saslScramClient = replacement
		let pending = Task<Void, Never> { try? await Task.sleep(for: .seconds(60)) }
		client.saslScramTask = pending
		defer { client.resetSASLNegotiation() }
		let sent = client.sentLines.compactMap { $0 as? String }
		resume.yield()
		await retired.value
		#expect(retired.isCancelled)
		#expect(client.saslScramClient === replacement)
		#expect(client.saslScramTask != nil)
		#expect(pending.isCancelled == false)
		#expect(client.sentLines.compactMap { $0 as? String } == sent)
	}

	@Test("A second wire challenge aborts rather than launching another derivation")
	func duplicateWireChallengeAborts() async throws {
		let (client, resume) = try await derivingClient()
		let task = try #require(client.saslScramTask)
		defer { resume.finish() }
		let challenge = Data("r=nonce-server,s=c2FsdA==,i=4096".utf8).base64EncodedString()
		try receive("AUTHENTICATE \(challenge)", on: client)
		#expect(task.isCancelled)
		#expect(client.saslScramTask == nil)
		#expect(client.sentLines.contains("AUTHENTICATE *"))
		let sent = client.sentLines.compactMap { $0 as? String }
		resume.yield()
		await task.value
		#expect(client.sentLines.compactMap { $0 as? String } == sent)
	}

	private func client(mechanism: String?, scram: SCRAMClient?) -> GLTTestClient {
		let client = GLTTestClient()
		client.saslMechanism = mechanism
		client.saslScramClient = scram
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
