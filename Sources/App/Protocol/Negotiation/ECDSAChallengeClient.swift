// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CryptoKit
import Foundation
import Security

/// Why an ECDSA-NIST256P-CHALLENGE exchange or key import failed.
nonisolated enum ECDSAChallengeError: Error, Equatable, Sendable {
	/// The server's challenge is not valid base64.
	case challengeNotBase64
	/// The decoded challenge is not ``ECDSAChallengeClient/challengeLength`` bytes.
	case challengeLength(Int)
	/// The key could not produce a signature.
	case signingFailed
	/// The data is not a P-256 private key in a supported encoding.
	case unsupportedKey
	/// The data is larger than any supported key encoding.
	case keyDataTooLarge
}

/** Client side of SASL `ECDSA-NIST256P-CHALLENGE`.

 The exchange is three messages. After the server's empty `+` the client sends
 the account name; the server answers with a 32-byte challenge; the client
 answers with an ECDSA signature over it. The object holds no state of its own:
 the session decides which message is due and calls the matching method.

 The challenge is signed as the digest itself. Atheme and the other servers
 built on libecdsaauth pass the 32 challenge bytes to `ECDSA_verify` as an
 already-computed hash, so hashing them again with SHA-256 produces a signature
 those servers reject. The signature goes out DER-encoded, which is what
 `ecdsatool sign` prints and the servers decode. */
nonisolated struct ECDSAChallengeClient: Sendable {
	static let mechanismName = "ECDSA-NIST256P-CHALLENGE"

	/// The length of the challenge the mechanism defines, which is also the
	/// size of the digest a P-256 signature covers.
	static let challengeLength = 32

	let privateKey: P256.Signing.PrivateKey
	/// The account the exchange names, sent as the authorization identity.
	let authorizationIdentity: String

	/// The first response: the account name. An empty name is sent as `+`.
	var identityPayload: Data {
		Data(authorizationIdentity.utf8)
	}

	/// The DER signature over the base64 challenge the server sent.
	func response(forEncodedChallenge encoded: String) throws -> Data {
		guard let challenge = Data(base64Encoded: encoded) else {
			throw ECDSAChallengeError.challengeNotBase64
		}

		return try signature(forChallenge: challenge)
	}

	/// The DER-encoded signature over `challenge`, which must be exactly
	/// ``challengeLength`` bytes.
	func signature(forChallenge challenge: Data) throws -> Data {
		guard challenge.count == Self.challengeLength else {
			throw ECDSAChallengeError.challengeLength(challenge.count)
		}

		let attributes: [CFString: Any] = [
			kSecAttrKeyType: kSecAttrKeyTypeECSECPrimeRandom,
			kSecAttrKeyClass: kSecAttrKeyClassPrivate,
			kSecAttrKeySizeInBits: 256,
		]
		var failure: Unmanaged<CFError>?

		guard let secKey = SecKeyCreateWithData(
			privateKey.x963Representation as CFData,
			attributes as CFDictionary,
			&failure
		) else {
			failure?.release()
			throw ECDSAChallengeError.signingFailed
		}
		/* The digest algorithm signs the bytes as they are, without hashing, and
		 answers with an X9.62 (DER) signature. */
		guard let signature = SecKeyCreateSignature(
			secKey,
			.ecdsaSignatureDigestX962SHA256,
			challenge as CFData,
			&failure
		) else {
			failure?.release()
			throw ECDSAChallengeError.signingFailed
		}

		return signature as Data
	}
}

/** The P-256 key SASL ECDSA signs with: how it is stored, shown and imported.

 The keychain item holds the base64 of the 32-byte raw representation. */
nonisolated enum ECDSASigningKey {
	/// The largest key file import reads. A PEM-encoded P-256 key is a few
	/// hundred bytes; anything past this is not one.
	static let maximumImportLength = 16384

	/// The length of a P-256 private scalar.
	private static let scalarLength = 32

	static func generate() -> P256.Signing.PrivateKey {
		P256.Signing.PrivateKey()
	}

	/// The string the keychain item holds for `key`.
	static func storedRepresentation(of key: P256.Signing.PrivateKey) -> String {
		key.rawRepresentation.base64EncodedString()
	}

	/// The key a keychain item's string holds, or nil when it is not one.
	static func privateKey(fromStored stored: String) -> P256.Signing.PrivateKey? {
		guard let raw = Data(base64Encoded: stored) else { return nil }
		return try? P256.Signing.PrivateKey(rawRepresentation: raw)
	}

	/** The public key as registration commands expect it: the base64 of the
	 33-byte compressed point. Atheme's `NickServ SET PUBKEY` takes this form,
	 and so does the output of `ecdsatool keygen`. */
	static func registrationPublicKey(of key: P256.Signing.PrivateKey) -> String {
		key.publicKey.compressedRepresentation.base64EncodedString()
	}

	/** A key from the contents of a file.

	 Accepts PEM text holding a PKCS #8 (`PRIVATE KEY`) or SEC1
	 (`EC PRIVATE KEY`, what `openssl ecparam -genkey` and `ecdsatool` write)
	 block, in which case other blocks such as `EC PARAMETERS` are skipped;
	 binary PKCS #8 DER; or the bare 32-byte scalar. */
	static func privateKey(importing data: Data) throws -> P256.Signing.PrivateKey {
		guard data.count <= maximumImportLength else {
			throw ECDSAChallengeError.keyDataTooLarge
		}

		if let text = String(data: data, encoding: .utf8), text.contains("-----BEGIN") {
			guard let block = privateKeyBlock(in: text),
			      let key = try? P256.Signing.PrivateKey(pemRepresentation: block)
			else {
				throw ECDSAChallengeError.unsupportedKey
			}

			return key
		}

		if let key = try? P256.Signing.PrivateKey(derRepresentation: data) {
			return key
		}
		if data.count == scalarLength, let key = try? P256.Signing.PrivateKey(rawRepresentation: data) {
			return key
		}

		throw ECDSAChallengeError.unsupportedKey
	}

	private static func privateKeyBlock(in text: String) -> String? {
		for label in ["PRIVATE KEY", "EC PRIVATE KEY"] {
			let begin = "-----BEGIN \(label)-----"
			let end = "-----END \(label)-----"

			if let start = text.range(of: begin), let finish = text.range(of: end, range: start.upperBound ..< text.endIndex) {
				return String(text[start.lowerBound ..< finish.upperBound])
			}
		}

		return nil
	}
}
