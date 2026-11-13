// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CryptoKit
import Foundation
@testable import Glasstual
import Security
import Testing

@MainActor
@Suite("SASL ECDSA-NIST256P-CHALLENGE")
struct ECDSAChallengeClientTests {
	/// A fixed scalar, so a failure reproduces.
	private let key: P256.Signing.PrivateKey
	private static let challenge = Data((0 ..< 32).map { UInt8($0 &* 7 &+ 3) })

	init() throws {
		key = try P256.Signing.PrivateKey(rawRepresentation: Data(1 ... 32))
	}

	private func client(identity: String = "account") -> ECDSAChallengeClient {
		ECDSAChallengeClient(privateKey: key, authorizationIdentity: identity)
	}

	/// Verifies as a server built on libecdsaauth does: the challenge is the
	/// digest, and the signature is X9.62 DER.
	private static func verifies(_ signature: Data, challenge: Data, publicKey: P256.Signing.PublicKey) -> Bool {
		let attributes: [CFString: Any] = [
			kSecAttrKeyType: kSecAttrKeyTypeECSECPrimeRandom,
			kSecAttrKeyClass: kSecAttrKeyClassPublic,
		]
		guard let secKey = SecKeyCreateWithData(publicKey.x963Representation as CFData, attributes as CFDictionary, nil) else {
			return false
		}

		return SecKeyVerifySignature(
			secKey,
			.ecdsaSignatureDigestX962SHA256,
			challenge as CFData,
			signature as CFData,
			nil
		)
	}

	@Test("The signature over the challenge verifies with the public key")
	func signatureVerifies() throws {
		let signature = try client().signature(forChallenge: Self.challenge)

		#expect(Self.verifies(signature, challenge: Self.challenge, publicKey: key.publicKey))
		#expect(Self.verifies(signature, challenge: Data(repeating: 0, count: 32), publicKey: key.publicKey) == false)
		#expect(Self.verifies(signature, challenge: Self.challenge, publicKey: P256.Signing.PrivateKey().publicKey) == false)
	}

	@Test("The signature is DER and covers the challenge itself, not its SHA-256")
	func signatureIsDERAndUnhashed() throws {
		let signature = try client().signature(forChallenge: Self.challenge)

		let parsed = try P256.Signing.ECDSASignature(derRepresentation: signature)
		let hashedCheck = key.publicKey.isValidSignature(parsed, for: Self.challenge)

		#expect(hashedCheck == false)
	}

	@Test("The response decodes the base64 challenge and signs it")
	func responseFromEncodedChallenge() throws {
		let response = try client().response(forEncodedChallenge: Self.challenge.base64EncodedString())

		#expect(Self.verifies(response, challenge: Self.challenge, publicKey: key.publicKey))
	}

	@Test("A challenge that is not base64 is refused")
	func challengeNotBase64() {
		#expect(throws: ECDSAChallengeError.challengeNotBase64) {
			try client().response(forEncodedChallenge: "not base64!")
		}
	}

	@Test("A challenge that is not 32 bytes is refused", arguments: [0, 1, 31, 33, 64])
	func challengeLength(length: Int) {
		let encoded = Data(repeating: 9, count: length).base64EncodedString()

		#expect(throws: ECDSAChallengeError.challengeLength(length)) {
			try client().response(forEncodedChallenge: encoded)
		}
	}

	@Test("The first response is the account name")
	func identityPayload() {
		#expect(client(identity: "Zoë").identityPayload == Data("Zoë".utf8))
		#expect(SASLPolicy.wireChunks(for: client(identity: "").identityPayload) == ["+"])
	}

	@Test("The registration key is the base64 of the 33-byte compressed point")
	func registrationPublicKey() throws {
		let encoded = ECDSASigningKey.registrationPublicKey(of: key)
		let decoded = try #require(Data(base64Encoded: encoded))

		#expect(decoded.count == 33)
		#expect([0x02, 0x03].contains(decoded[0]))
		#expect(decoded == key.publicKey.compressedRepresentation)
	}

	@Test("The stored representation reads back as the same key")
	func storedRepresentationRoundTrips() {
		let stored = ECDSASigningKey.storedRepresentation(of: key)

		#expect(ECDSASigningKey.privateKey(fromStored: stored)?.rawRepresentation == key.rawRepresentation)
		#expect(ECDSASigningKey.privateKey(fromStored: "not base64!") == nil)
		#expect(ECDSASigningKey.privateKey(fromStored: Data(1 ... 8).base64EncodedString()) == nil)
	}

	@Test("A generated key is exported as PEM and imported again")
	func importsPEM() throws {
		let generated = ECDSASigningKey.generate()
		let imported = try ECDSASigningKey.privateKey(importing: Data(generated.pemRepresentation.utf8))

		#expect(imported.rawRepresentation == generated.rawRepresentation)
	}

	@Test("PEM text with other blocks around the key still imports")
	func importsPEMWithParameters() throws {
		let generated = ECDSASigningKey.generate()
		let text = """
		-----BEGIN EC PARAMETERS-----
		BggqhkjOPQMBBw==
		-----END EC PARAMETERS-----
		\(generated.pemRepresentation)
		"""
		let imported = try ECDSASigningKey.privateKey(importing: Data(text.utf8))

		#expect(imported.rawRepresentation == generated.rawRepresentation)
	}

	@Test("PKCS #8 DER and the bare scalar import")
	func importsDERAndRaw() throws {
		let generated = ECDSASigningKey.generate()

		let fromDER = try ECDSASigningKey.privateKey(importing: generated.derRepresentation)
		let fromRaw = try ECDSASigningKey.privateKey(importing: generated.rawRepresentation)

		#expect(fromDER.rawRepresentation == generated.rawRepresentation)
		#expect(fromRaw.rawRepresentation == generated.rawRepresentation)
	}

	@Test("Data that is not a usable P-256 private key is refused")
	func refusesUnsupportedKeys() {
		let other = P384.Signing.PrivateKey()
		let encrypted = "-----BEGIN ENCRYPTED PRIVATE KEY-----\nAAAA\n-----END ENCRYPTED PRIVATE KEY-----\n"
		let samples = [
			Data("hello".utf8),
			Data(),
			Data(other.pemRepresentation.utf8),
			Data(encrypted.utf8),
			Data("-----BEGIN PRIVATE KEY-----\n!!!\n-----END PRIVATE KEY-----\n".utf8),
		]

		for sample in samples {
			#expect(throws: ECDSAChallengeError.unsupportedKey) {
				try ECDSASigningKey.privateKey(importing: sample)
			}
		}
	}

	@Test("Oversized data is refused before it is parsed")
	func refusesOversizedKeyData() {
		let data = Data(repeating: 65, count: ECDSASigningKey.maximumImportLength + 1)

		#expect(throws: ECDSAChallengeError.keyDataTooLarge) {
			try ECDSASigningKey.privateKey(importing: data)
		}
	}

	@Test("The wire chunks of binary data are the base64 of the bytes")
	func binaryWireChunks() {
		#expect(SASLPolicy.wireChunks(for: Data([0xFF, 0xFE, 0xFD])) == ["//79"])
		#expect(SASLPolicy.wireChunks(for: Data(repeating: 1, count: 300)).map(\.count) == [400, 1])
	}
}
