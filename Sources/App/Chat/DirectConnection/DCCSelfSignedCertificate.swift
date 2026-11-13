// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CryptoKit
import Foundation

/** A self-signed X.509 v3 certificate for a P-256 key, encoded as DER.

 Secure DCC peers do not validate certificates against an authority: a client
 such as KVIrc presents whatever its user configured, and both ends decide on
 the fingerprint. The certificate only has to be well formed enough for TLS to
 carry it and for the other end to hash it, so this writes the handful of DER
 types an X.509 certificate needs rather than depending on a package.

 The certificate is `ecdsa-with-SHA256`, version 3, with BasicConstraints
 `CA:FALSE`, KeyUsage `digitalSignature` and ExtendedKeyUsage `serverAuth` and
 `clientAuth`. The issuer and subject are the same single common name. */
nonisolated enum DCCSelfSignedCertificate {
	enum BuildError: Error, Equatable {
		/// An X.509 serial number is a positive integer, so it cannot be zero.
		case zeroSerialNumber
		/// RFC 5280 limits a serial number to 20 octets, counting the sign
		/// octet its encoding needs when the high bit is set.
		case oversizedSerialNumber
		/// The validity period ends before it starts.
		case invalidValidityPeriod
	}

	/// The common name every DCC certificate carries. It names the application
	/// and nothing about the user, because TLS 1.2 sends certificates in clear.
	static let commonName = "Glasstual DCC"

	/// Builds and signs the certificate.
	///
	/// - Parameter serialNumber: the serial's big-endian magnitude. Leading
	///   zero octets are dropped and a sign octet is added where the encoding
	///   needs one, so any non-zero value is accepted as positive.
	static func make(
		privateKey: P256.Signing.PrivateKey,
		commonName: String = commonName,
		serialNumber: [UInt8],
		notBefore: Date,
		notAfter: Date
	) throws -> Data {
		let magnitude = Array(serialNumber.drop { $0 == 0 })
		guard magnitude.isEmpty == false else { throw BuildError.zeroSerialNumber }
		let signOctets = magnitude[0] & 0x80 == 0 ? 0 : 1
		guard magnitude.count + signOctets <= 20 else { throw BuildError.oversizedSerialNumber }
		guard notBefore < notAfter else { throw BuildError.invalidValidityPeriod }

		let signatureAlgorithm = DERWriter.sequence([DERWriter.objectIdentifier(OID.ecdsaWithSHA256)])
		let name = DERWriter.sequence([
			DERWriter.set([
				DERWriter.sequence([
					DERWriter.objectIdentifier(OID.commonName),
					DERWriter.utf8String(commonName),
				]),
			]),
		])

		let tbsCertificate = DERWriter.sequence([
			DERWriter.contextSpecific(0, DERWriter.integer([2])),
			DERWriter.integer(magnitude),
			signatureAlgorithm,
			name,
			DERWriter.sequence([DERWriter.time(notBefore), DERWriter.time(notAfter)]),
			name,
			privateKey.publicKey.derRepresentation,
			DERWriter.contextSpecific(3, DERWriter.sequence(extensions)),
		])

		let signature = try privateKey.signature(for: tbsCertificate).derRepresentation

		return DERWriter.sequence([
			tbsCertificate,
			signatureAlgorithm,
			DERWriter.bitString(signature),
		])
	}

	/// A random 128-bit serial, as RFC 5280 recommends for unpredictability.
	static func randomSerialNumber() -> [UInt8] {
		var generator = SystemRandomNumberGenerator()
		var bytes = (0 ..< 16).map { _ in UInt8.random(in: .min ... .max, using: &generator) }
		/* A zero serial is the one value `make` refuses, so it is never handed
		 out: the chance is 2^-128, but nothing here has to rely on that. */
		if bytes.allSatisfy({ $0 == 0 }) {
			bytes[bytes.count - 1] = 1
		}
		return bytes
	}

	private static var extensions: [Data] {
		[
			certificateExtension(
				OID.basicConstraints,
				critical: true,
				value: DERWriter.sequence([])
			),
			certificateExtension(
				OID.keyUsage,
				critical: true,
				/* `digitalSignature` is bit 0, the high bit of the first octet;
					the other seven bits of that octet are unused. */
				value: DERWriter.bitString(Data([0x80]), unusedBits: 7)
			),
			certificateExtension(
				OID.extendedKeyUsage,
				critical: false,
				value: DERWriter.sequence([
					DERWriter.objectIdentifier(OID.serverAuthentication),
					DERWriter.objectIdentifier(OID.clientAuthentication),
				])
			),
		]
	}

	private static func certificateExtension(_ identifier: [UInt64], critical: Bool, value: Data) -> Data {
		var fields = [DERWriter.objectIdentifier(identifier)]
		/* DER omits a field equal to its default, and `critical` defaults to
		 false. */
		if critical {
			fields.append(DERWriter.boolean(true))
		}
		fields.append(DERWriter.octetString(value))
		return DERWriter.sequence(fields)
	}

	private enum OID {
		static let ecdsaWithSHA256: [UInt64] = [1, 2, 840, 10045, 4, 3, 2]
		static let commonName: [UInt64] = [2, 5, 4, 3]
		static let basicConstraints: [UInt64] = [2, 5, 29, 19]
		static let keyUsage: [UInt64] = [2, 5, 29, 15]
		static let extendedKeyUsage: [UInt64] = [2, 5, 29, 37]
		static let serverAuthentication: [UInt64] = [1, 3, 6, 1, 5, 5, 7, 3, 1]
		static let clientAuthentication: [UInt64] = [1, 3, 6, 1, 5, 5, 7, 3, 2]
	}
}

/// The DER encodings a certificate needs, each returning a complete
/// tag-length-value element.
nonisolated enum DERWriter {
	static func sequence(_ elements: [Data]) -> Data {
		element(tag: 0x30, contents: elements.reduce(into: Data()) { $0.append($1) })
	}

	static func set(_ elements: [Data]) -> Data {
		/* DER sorts the members of a SET OF by their encodings. */
		element(tag: 0x31, contents: elements.sorted { $0.lexicographicallyPrecedes($1) }
			.reduce(into: Data()) { $0.append($1) })
	}

	static func boolean(_ value: Bool) -> Data {
		element(tag: 0x01, contents: Data([value ? 0xFF : 0x00]))
	}

	/// A non-negative integer from its big-endian magnitude.
	static func integer(_ magnitude: [UInt8]) -> Data {
		var octets = Array(magnitude.drop { $0 == 0 })
		if octets.isEmpty {
			octets = [0]
		} else if octets[0] & 0x80 != 0 {
			/* The high bit is the sign bit, so a magnitude that sets it needs a
			 leading zero to stay positive. */
			octets.insert(0, at: 0)
		}
		return element(tag: 0x02, contents: Data(octets))
	}

	static func bitString(_ bytes: Data, unusedBits: UInt8 = 0) -> Data {
		element(tag: 0x03, contents: Data([unusedBits]) + bytes)
	}

	static func octetString(_ bytes: Data) -> Data {
		element(tag: 0x04, contents: bytes)
	}

	static func utf8String(_ string: String) -> Data {
		element(tag: 0x0C, contents: Data(string.utf8))
	}

	static func objectIdentifier(_ arcs: [UInt64]) -> Data {
		precondition(arcs.count >= 2 && arcs[0] <= 2, "An object identifier has at least two arcs")
		var contents = base128(arcs[0] * 40 + arcs[1])
		for arc in arcs.dropFirst(2) {
			contents.append(base128(arc))
		}
		return element(tag: 0x06, contents: contents)
	}

	/// A certificate validity time: UTCTime through 2049 and GeneralizedTime
	/// from 2050, as RFC 5280 requires.
	static func time(_ date: Date) -> Data {
		var calendar = Calendar(identifier: .gregorian)
		calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
		let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
		let year = parts.year ?? 1970
		let rest = [parts.month, parts.day, parts.hour, parts.minute, parts.second]
			.map { twoDigits($0 ?? 0) }
			.joined()

		if year < 2050 {
			return element(tag: 0x17, contents: Data((twoDigits(year % 100) + rest + "Z").utf8))
		}
		return element(tag: 0x18, contents: Data((String(year) + rest + "Z").utf8))
	}

	/// An explicit context-specific tag around one element.
	static func contextSpecific(_ number: UInt8, _ element: Data) -> Data {
		Self.element(tag: 0xA0 | number, contents: element)
	}

	private static func element(tag: UInt8, contents: Data) -> Data {
		var encoded = Data([tag])
		encoded.append(length(contents.count))
		encoded.append(contents)
		return encoded
	}

	private static func length(_ count: Int) -> Data {
		guard count >= 0x80 else { return Data([UInt8(count)]) }
		var octets: [UInt8] = []
		var remaining = count
		while remaining > 0 {
			octets.insert(UInt8(truncatingIfNeeded: remaining), at: 0)
			remaining >>= 8
		}
		return Data([0x80 | UInt8(octets.count)] + octets)
	}

	private static func base128(_ value: UInt64) -> Data {
		var octets = [UInt8(value & 0x7F)]
		var remaining = value >> 7
		while remaining > 0 {
			octets.insert(UInt8(remaining & 0x7F) | 0x80, at: 0)
			remaining >>= 7
		}
		return Data(octets)
	}

	private static func twoDigits(_ value: Int) -> String {
		value < 10 ? "0\(value)" : String(value)
	}
}
