import Foundation
@testable import Glasstual
import Testing

/** *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2010 - 2018 Codeux Software, LLC & respective contributors.
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
@MainActor
@Suite("SCRAM-SHA-256 client")
struct TLOSCRAMClientTests {
	private let serverFirst =
		"r=rOprNGfwEbeRWgbNEkqO%hvYDpWUa2RaTCAfuxFIlj)hNlF$k0,s=W22ZaJ0SNY7soEsUEjb6gQ==,i=4096"

	@Test("The client's first message names the user and the client nonce")
	func clientFirstMessage() {
		let client = exampleClient()

		#expect(client.clientFirstMessage == "n,,n=user,r=rOprNGfwEbeRWgbNEkqO")
		#expect(client.state == .sentClientFirst)
	}

	@Test("The client's final message matches the RFC 7677 test vector")
	func clientFinalMessageMatchesRFC7677Vector() throws {
		let client = exampleClient()
		_ = client.clientFirstMessage

		let clientFinal = try client.clientFinalMessage(forServerFirstMessage: serverFirst)
		let expected =
			"c=biws,r=rOprNGfwEbeRWgbNEkqO%hvYDpWUa2RaTCAfuxFIlj)hNlF$k0,p=dHzbZapWIk4jUhN+Ute9ytag9zjfMHgsqmmiz7AndVQ="

		#expect(clientFinal == expected)
	}

	@Test("The right server signature authenticates the exchange")
	func verifyServerFinalMessageSucceedsForCorrectSignature() throws {
		let client = exampleClient()
		_ = client.clientFirstMessage
		_ = try client.clientFinalMessage(forServerFirstMessage: serverFirst)

		try client.verifyServerFinalMessage("v=6rriTRBi23WpRR/wtup+mMhUZUn/dB5nLTJRsjl95G4=")

		#expect(client.state == .authenticated)
	}

	@Test("A wrong server signature fails the exchange")
	func verifyServerFinalMessageRejectsWrongSignature() throws {
		let client = exampleClient()
		_ = client.clientFirstMessage
		_ = try client.clientFinalMessage(forServerFirstMessage: serverFirst)

		let error = #expect(throws: (any Error).self) {
			try client.verifyServerFinalMessage("v=7rriTRBi23WpRR/wtup+mMhUZUn/dB5nLTJRsjl95G4=")
		}
		let code = error.map { ($0 as NSError).code }

		#expect(code == SCRAMClientErrorCode.serverSignatureMismatch.rawValue)
		#expect(client.state == .failed)
	}

	@Test("The server nonce has to begin with the client nonce")
	func serverNonceMustBeginWithClientNonce() {
		expectFailure(
			for: "r=differentNonce,s=W22ZaJ0SNY7soEsUEjb6gQ==,i=4096",
			code: .nonceMismatch
		)
	}

	@Test("An iteration count below the minimum is rejected")
	func iterationCountBelowMinimumIsRejected() {
		expectFailure(
			for: "r=rOprNGfwEbeRWgbNEkqO%hvYDpWUa2RaTCAfuxFIlj)hNlF$k0,s=W22ZaJ0SNY7soEsUEjb6gQ==,i=1024",
			code: .iterationCountTooLow
		)
	}

	@Test("A server-first message that parses into nothing is rejected")
	func malformedServerFirstMessageIsRejected() {
		expectFailure(for: "nonsense", code: .malformedServerMessage)
	}

	private func exampleClient() -> SCRAMClient {
		SCRAMClient(username: "user", password: "pencil", clientNonce: "rOprNGfwEbeRWgbNEkqO")
	}

	private func expectFailure(
		for serverMessage: String,
		code: SCRAMClientErrorCode,
		sourceLocation: SourceLocation = #_sourceLocation
	) {
		let client = exampleClient()
		_ = client.clientFirstMessage

		let error = #expect(throws: (any Error).self, sourceLocation: sourceLocation) {
			try client.clientFinalMessage(forServerFirstMessage: serverMessage)
		}
		let thrownCode = error.map { ($0 as NSError).code }

		#expect(thrownCode == code.rawValue, sourceLocation: sourceLocation)
	}
}
