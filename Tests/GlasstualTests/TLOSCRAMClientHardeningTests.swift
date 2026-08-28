/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \\ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\\___/_/\\_\\__|\\__,_|\\__,_|_|
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
struct TLOSCRAMClientHardeningTests {
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
	func excessiveIterationCountsAreRejected(_ iterations: String) {
		let client = exampleClient()
		_ = client.clientFirstMessage

		do {
			_ = try client.clientFinalMessage(forServerFirstMessage: serverFirst(iterations: iterations))
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
	func iterationCountAtTheCeilingIsAccepted() throws {
		let client = exampleClient()
		_ = client.clientFirstMessage

		_ = try client.clientFinalMessage(forServerFirstMessage: serverFirst(iterations: "600000"))

		#expect(client.state == .sentClientFinal)
	}

	/// The offloaded derivation has to agree with the RFC 7677 vector the
	/// synchronous path is checked against.
	@Test
	func offloadedDerivationMatchesTheSynchronousResult() async throws {
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
	func scramWithAVerifiedServerFinalMessageIsSatisfied() throws {
		let scram = SCRAMClient(username: "user", password: "pencil", clientNonce: "rOprNGfwEbeRWgbNEkqO")
		_ = scram.clientFirstMessage
		_ = try scram.clientFinalMessage(
			forServerFirstMessage:
			"r=rOprNGfwEbeRWgbNEkqO%hvYDpWUa2RaTCAfuxFIlj)hNlF$k0,s=W22ZaJ0SNY7soEsUEjb6gQ==,i=4096"
		)
		try scram.verifyServerFinalMessage("v=6rriTRBi23WpRR/wtup+mMhUZUn/dB5nLTJRsjl95G4=")

		let client = client(mechanism: SCRAMClient.mechanismName, scram: scram)

		#expect(client.scramMutualAuthenticationIsSatisfied())
	}
}
