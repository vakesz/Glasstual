// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CryptoKit
import Foundation
import Security

/** What a secure DCC peer presented, read once from the handshake.

 Only the leaf certificate matters: peers present self-signed certificates and
 nothing is evaluated against an authority, so the fingerprint and the key are
 the whole of what is decided on. Everything here is plain values, so the
 description can leave the TLS validator and reach whoever decides. */
nonisolated struct DCCPeerCertificate: Equatable, Sendable {
	/// The kind of key the certificate certifies.
	enum KeyAlgorithm: Equatable, Sendable {
		case rsa
		case ellipticCurve
		/// A key Security does not describe as RSA or elliptic curve, such as
		/// Ed25519. It is refused because its strength is not judged here.
		case other
	}

	enum KeyStrength: Equatable, Sendable {
		case acceptable
		/// Shorter than the floor for its algorithm, or an algorithm with no
		/// floor at all.
		case weak
	}

	/// The smallest RSA modulus accepted, in bits.
	static let minimumRSAKeySize = 2048
	/// The smallest elliptic-curve field accepted, in bits.
	static let minimumEllipticCurveKeySize = 256

	let der: Data
	let fingerprint: DCCCertificateFingerprint
	/// For display beside the SHA-256 fingerprint only; never compared.
	let sha1: Data
	/// What Security summarises the subject as, usually its common name.
	let subjectSummary: String?
	let keyAlgorithm: KeyAlgorithm
	let keySize: Int
	let notBefore: Date?
	let notAfter: Date?

	var keyStrength: KeyStrength {
		switch keyAlgorithm {
		case .rsa where keySize >= Self.minimumRSAKeySize,
		     .ellipticCurve where keySize >= Self.minimumEllipticCurveKeySize:
			.acceptable
		case .rsa, .ellipticCurve, .other:
			.weak
		}
	}

	/// Whether `date` is outside the validity period. Shown, never decided on:
	/// a pin does not depend on dates.
	func isExpired(at date: Date) -> Bool {
		if let notBefore, date < notBefore {
			return true
		}
		if let notAfter, date > notAfter {
			return true
		}
		return false
	}

	/// Reads a DER certificate, or `nil` when Security cannot parse it or find
	/// its key.
	init?(der: Data) {
		guard let certificate = SecCertificateCreateWithData(nil, der as CFData) else {
			return nil
		}
		self.init(certificate: certificate, der: der)
	}

	/// The leaf of the chain a handshake presented, or `nil` when the chain is
	/// empty or unreadable.
	static func inspect(_ trust: sec_trust_t) -> DCCPeerCertificate? {
		let reference = sec_trust_copy_ref(trust).takeRetainedValue()
		guard let chain = SecTrustCopyCertificateChain(reference) as? [SecCertificate],
		      let leaf = chain.first
		else {
			return nil
		}
		return DCCPeerCertificate(certificate: leaf, der: SecCertificateCopyData(leaf) as Data)
	}

	/** The leaf of the peer chain a finished handshake's metadata holds, or
	 `nil` when there is none.

	 A TLS 1.2 session resumed by its identifier skips the validator, and
	 carries the chain from the handshake that created it. */
	static func inspect(_ metadata: sec_protocol_metadata_t) -> DCCPeerCertificate? {
		var leaf: SecCertificate?
		_ = sec_protocol_metadata_access_peer_certificate_chain(metadata) { certificate in
			if leaf == nil {
				leaf = sec_certificate_copy_ref(certificate).takeRetainedValue()
			}
		}
		guard let leaf else { return nil }
		return DCCPeerCertificate(certificate: leaf, der: SecCertificateCopyData(leaf) as Data)
	}

	private init?(certificate: SecCertificate, der: Data) {
		guard let key = SecCertificateCopyKey(certificate),
		      let attributes = SecKeyCopyAttributes(key) as? [CFString: Any]
		else {
			return nil
		}

		let type = attributes[kSecAttrKeyType] as? String
		if type == kSecAttrKeyTypeRSA as String {
			keyAlgorithm = .rsa
		} else if type == kSecAttrKeyTypeECSECPrimeRandom as String {
			keyAlgorithm = .ellipticCurve
		} else {
			keyAlgorithm = .other
		}
		keySize = (attributes[kSecAttrKeySizeInBits] as? Int) ?? 0

		self.der = der
		fingerprint = DCCCertificateFingerprint(certificate: der)
		sha1 = Data(Insecure.SHA1.hash(data: der))
		subjectSummary = SecCertificateCopySubjectSummary(certificate) as String?
		notBefore = SecCertificateCopyNotValidBeforeDate(certificate) as Date?
		notAfter = SecCertificateCopyNotValidAfterDate(certificate) as Date?
	}
}
