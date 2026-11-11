// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing

/// SCRAM-SHA-512 is RFC 5802 over SHA-512. The vector reuses the RFC 7677
/// inputs; its outputs were computed independently from the RFC 5802 §3
/// formulas with Python's `hashlib` and `hmac`.
@MainActor
@Suite("SCRAM-SHA-512 client")
struct SCRAMSHA512ClientTests {
	private let serverFirst =
		"r=rOprNGfwEbeRWgbNEkqO%hvYDpWUa2RaTCAfuxFIlj)hNlF$k0,s=W22ZaJ0SNY7soEsUEjb6gQ==,i=4096"

	private func exampleSession() -> SCRAMClient {
		SCRAMClient(hash: .sha512, username: "user", password: "pencil", clientNonce: "rOprNGfwEbeRWgbNEkqO")
	}

	@Test("The client's final message matches the SHA-512 vector")
	func clientFinalMessageMatchesVector() async throws {
		let session = exampleSession()
		_ = session.clientFirstMessage

		let clientFinal = try await session.clientFinalMessage(forServerFirstMessage: serverFirst)

		#expect(clientFinal == "c=biws,r=rOprNGfwEbeRWgbNEkqO%hvYDpWUa2RaTCAfuxFIlj)hNlF$k0,"
			+ "p=gMGXRcevScNtxZ6/8lQYpGtnsNAc3mGcmNomv+xnoOMw+3R2xNJdMNnzMlTN8PPC6wdp6dybEmDYXYTxwnYPJQ==")
	}

	@Test("The right server signature authenticates, and a flipped byte does not")
	func serverSignatureIsVerified() async throws {
		let verifier = "ZQnYEgWQMFmmsM8aQMF0nDDCy/AgCzkwk8CmMZYcMg0vSVlKDanekLtifDSeVGT4+5ZxXnJq199RVG2rR7N7Zw=="

		let session = exampleSession()
		_ = session.clientFirstMessage
		_ = try await session.clientFinalMessage(forServerFirstMessage: serverFirst)
		try session.verifyServerFinalMessage("v=\(verifier)")
		#expect(session.state == .authenticated)

		var flipped = try #require(Data(base64Encoded: verifier))
		flipped[0] ^= 0x01
		let forged = exampleSession()
		_ = forged.clientFirstMessage
		_ = try await forged.clientFinalMessage(forServerFirstMessage: serverFirst)
		let error = #expect(throws: SCRAMClientError.self) {
			try forged.verifyServerFinalMessage("v=\(flipped.base64EncodedString())")
		}
		#expect(error?.code == .serverSignatureMismatch)
	}

	@Test("A mandatory extension in the server's first message fails the exchange", arguments: SCRAMHash.allCases)
	func mandatoryExtensionFails(_ hash: SCRAMHash) async {
		let session = SCRAMClient(hash: hash, username: "user", password: "pencil", clientNonce: "rOprNGfwEbeRWgbNEkqO")
		_ = session.clientFirstMessage

		let error = await #expect(throws: SCRAMClientError.self) {
			try await session.clientFinalMessage(forServerFirstMessage: "m=ext," + serverFirst)
		}
		#expect(error?.code == .unsupportedMandatoryExtension)
		#expect(session.state == .failed)
	}

	@Test("PBKDF2-HMAC-SHA512 matches the known answers and derives 64 bytes")
	func pbkdf2SHA512KnownAnswers() throws {
		let one = try #require(SCRAMClient.pbkdf2(password: "password", salt: Data("salt".utf8), iterations: 1, hash: .sha512))
		let many = try #require(SCRAMClient.pbkdf2(
			password: "password",
			salt: Data("salt".utf8),
			iterations: 4096,
			hash: .sha512
		))

		#expect(one.count == 64)
		#expect(one.hexString == "867f70cf1ade02cff3752599a3a53dc4af34c7a669815ae5d513554e1c8cf252"
			+ "c02d470a285a0501bad999bfe943c08f050235d7d68b1da55e63f73b60a57fce")
		#expect(many.hexString == "d197b1b33db0143e018b12f3d1d1479e6cdebdcc97c5c0f87f6902e072f457b5"
			+ "143f30602641b3d55cd335988cb36b84376060ecd532e039b742a239434af2d5")
	}

	@Test("Each hash names its mechanism and back")
	func hashMapsToMechanism() {
		for hash in SCRAMHash.allCases {
			#expect(SCRAMHash(mechanism: hash.mechanism) == hash)
		}
		#expect(SCRAMHash(mechanism: .plain) == nil)
	}
}

private extension Data {
	var hexString: String {
		map { String(format: "%02x", $0) }.joined()
	}
}
