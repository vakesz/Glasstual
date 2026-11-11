// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CryptoKit
import Foundation
@testable import Glasstual
import Security
import Testing

/// Certificates for the peer side of the trust tests, including RSA ones the
/// application never makes.
enum PeerCertificateFixture {
	struct FixtureError: Error {}

	static func ellipticCurve() throws -> Data {
		try DCCLocalIdentity.generate().certificate
	}

	/// A self-signed RSA certificate with a `bits`-bit modulus.
	static func rsa(bits: Int) throws -> Data {
		let attributes: [CFString: Any] = [kSecAttrKeyType: kSecAttrKeyTypeRSA, kSecAttrKeySizeInBits: bits]
		guard let privateKey = SecKeyCreateRandomKey(attributes as CFDictionary, nil),
		      let publicKey = SecKeyCopyPublicKey(privateKey),
		      let pkcs1 = SecKeyCopyExternalRepresentation(publicKey, nil) as Data?
		else { throw FixtureError() }

		let null = Data([0x05, 0x00])
		let algorithm = DERWriter.sequence([DERWriter.objectIdentifier([1, 2, 840, 113_549, 1, 1, 11]), null])
		let name = DERWriter.sequence([DERWriter.set([DERWriter.sequence([
			DERWriter.objectIdentifier([2, 5, 4, 3]), DERWriter.utf8String("RSA peer"),
		])])])
		let subjectPublicKeyInfo = DERWriter.sequence([
			DERWriter.sequence([DERWriter.objectIdentifier([1, 2, 840, 113_549, 1, 1, 1]), null]),
			DERWriter.bitString(pkcs1),
		])
		let tbs = DERWriter.sequence([
			DERWriter.contextSpecific(0, DERWriter.integer([2])),
			DERWriter.integer([0x2A]),
			algorithm,
			name,
			DERWriter.sequence([
				DERWriter.time(Date(timeIntervalSince1970: 1_700_000_000)),
				DERWriter.time(Date(timeIntervalSince1970: 2_000_000_000)),
			]),
			name,
			subjectPublicKeyInfo,
		])
		guard let signature = SecKeyCreateSignature(
			privateKey, .rsaSignatureMessagePKCS1v15SHA256, tbs as CFData, nil
		) as Data? else { throw FixtureError() }
		return DERWriter.sequence([tbs, algorithm, DERWriter.bitString(signature)])
	}

	static func trust(for der: Data) throws -> sec_trust_t {
		guard let certificate = SecCertificateCreateWithData(nil, der as CFData) else { throw FixtureError() }
		var trust: SecTrust?
		guard SecTrustCreateWithCertificates(certificate, SecPolicyCreateBasicX509(), &trust) == errSecSuccess,
		      let trust, let wrapped = sec_trust_create(trust)
		else { throw FixtureError() }
		return wrapped
	}
}

@Suite("DCC peer certificate")
struct DCCPeerCertificateTests {
	@Test("A P-256 certificate is acceptable and described by its key and digests")
	func ellipticCurve() throws {
		let der = try PeerCertificateFixture.ellipticCurve()
		let certificate = try #require(DCCPeerCertificate(der: der))

		#expect(certificate.keyAlgorithm == .ellipticCurve)
		#expect(certificate.keySize == 256)
		#expect(certificate.keyStrength == .acceptable)
		#expect(certificate.fingerprint == DCCCertificateFingerprint(certificate: der))
		#expect(certificate.sha1 == Data(Insecure.SHA1.hash(data: der)))
		#expect(certificate.subjectSummary == DCCSelfSignedCertificate.commonName)
	}

	@Test("RSA keys are judged against the 2048-bit floor", arguments: [(1024, false), (2048, true)])
	func rsa(bits: Int, acceptable: Bool) throws {
		let certificate = try #require(DCCPeerCertificate(der: PeerCertificateFixture.rsa(bits: bits)))

		#expect(certificate.keyAlgorithm == .rsa)
		#expect(certificate.keySize == bits)
		#expect(certificate.keyStrength == (acceptable ? .acceptable : .weak))
	}

	@Test("Inspecting a handshake's trust reads its leaf certificate")
	func inspect() throws {
		let der = try PeerCertificateFixture.ellipticCurve()
		let certificate = try #require(DCCPeerCertificate.inspect(PeerCertificateFixture.trust(for: der)))
		#expect(certificate.der == der)
	}

	@Test("Bytes that are not a certificate are not read as one")
	func garbage() {
		#expect(DCCPeerCertificate(der: Data([0x30, 0x03, 0x02, 0x01, 0x00])) == nil)
	}

	@Test("Dates outside the validity period are reported, not decided on")
	func expiry() throws {
		let certificate = try #require(DCCPeerCertificate(der: PeerCertificateFixture.rsa(bits: 2048)))
		#expect(certificate.isExpired(at: Date(timeIntervalSince1970: 1_600_000_000)))
		#expect(certificate.isExpired(at: Date(timeIntervalSince1970: 1_800_000_000)) == false)
		#expect(certificate.isExpired(at: Date(timeIntervalSince1970: 2_100_000_000)))
	}
}
