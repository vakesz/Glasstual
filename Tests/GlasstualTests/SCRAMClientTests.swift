// Copyright (c) 2010 - 2018 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing

@MainActor
@Suite("SCRAM-SHA-256 client")
struct SCRAMClientTests {
	private let serverFirst =
		"r=rOprNGfwEbeRWgbNEkqO%hvYDpWUa2RaTCAfuxFIlj)hNlF$k0,s=W22ZaJ0SNY7soEsUEjb6gQ==,i=4096"

	@Test("The client's first message names the user and the client nonce")
	func clientFirstMessage() {
		let client = exampleClient()

		#expect(client.clientFirstMessage == "n,,n=user,r=rOprNGfwEbeRWgbNEkqO")
		#expect(client.state == .sentClientFirst)
	}

	@Test("The client's final message matches the RFC 7677 test vector")
	func clientFinalMessageMatchesRFC7677Vector() async throws {
		let client = exampleClient()
		_ = client.clientFirstMessage

		let clientFinal = try await client.clientFinalMessage(forServerFirstMessage: serverFirst)
		let expected =
			"c=biws,r=rOprNGfwEbeRWgbNEkqO%hvYDpWUa2RaTCAfuxFIlj)hNlF$k0,p=dHzbZapWIk4jUhN+Ute9ytag9zjfMHgsqmmiz7AndVQ="

		#expect(clientFinal == expected)
	}

	@Test("The right server signature authenticates the exchange")
	func verifyServerFinalMessageSucceedsForCorrectSignature() async throws {
		let client = exampleClient()
		_ = client.clientFirstMessage
		_ = try await client.clientFinalMessage(forServerFirstMessage: serverFirst)

		try client.verifyServerFinalMessage("v=6rriTRBi23WpRR/wtup+mMhUZUn/dB5nLTJRsjl95G4=")

		#expect(client.state == .authenticated)
	}

	@Test("A wrong server signature fails the exchange")
	func verifyServerFinalMessageRejectsWrongSignature() async throws {
		let client = exampleClient()
		_ = client.clientFirstMessage
		_ = try await client.clientFinalMessage(forServerFirstMessage: serverFirst)

		let error = #expect(throws: (any Error).self) {
			try client.verifyServerFinalMessage("v=7rriTRBi23WpRR/wtup+mMhUZUn/dB5nLTJRsjl95G4=")
		}
		let code = error.map { ($0 as NSError).code }

		#expect(code == SCRAMClientErrorCode.serverSignatureMismatch.rawValue)
		#expect(client.state == .failed)
	}

	@Test("The server nonce has to begin with the client nonce")
	func serverNonceMustBeginWithClientNonce() async {
		await expectFailure(
			for: "r=differentNonce,s=W22ZaJ0SNY7soEsUEjb6gQ==,i=4096",
			code: .nonceMismatch
		)
	}

	@Test("An iteration count below the minimum is rejected")
	func iterationCountBelowMinimumIsRejected() async {
		await expectFailure(
			for: "r=rOprNGfwEbeRWgbNEkqO%hvYDpWUa2RaTCAfuxFIlj)hNlF$k0,s=W22ZaJ0SNY7soEsUEjb6gQ==,i=1024",
			code: .iterationCountTooLow
		)
	}

	@Test("A server-first message that parses into nothing is rejected")
	func malformedServerFirstMessageIsRejected() async {
		await expectFailure(for: "nonsense", code: .malformedServerMessage)
	}

	private func exampleClient() -> SCRAMClient {
		SCRAMClient(username: "user", password: "pencil", clientNonce: "rOprNGfwEbeRWgbNEkqO")
	}

	private func expectFailure(
		for serverMessage: String,
		code: SCRAMClientErrorCode,
		sourceLocation: SourceLocation = #_sourceLocation
	) async {
		let client = exampleClient()
		_ = client.clientFirstMessage

		let error = await #expect(throws: (any Error).self, sourceLocation: sourceLocation) {
			try await client.clientFinalMessage(forServerFirstMessage: serverMessage)
		}
		let thrownCode = error.map { ($0 as NSError).code }

		#expect(thrownCode == code.rawValue, sourceLocation: sourceLocation)
	}
}
