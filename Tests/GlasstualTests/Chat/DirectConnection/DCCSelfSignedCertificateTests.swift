// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CryptoKit
import Foundation
@testable import Glasstual
import Security
import Testing

@Suite("Self-signed DCC certificate")
struct DCCSelfSignedCertificateTests {
	private static let notBefore = Date(timeIntervalSince1970: 1_700_000_000)
	private static let notAfter = Date(timeIntervalSince1970: 2_000_000_000)

	private static func make(
		key: P256.Signing.PrivateKey = P256.Signing.PrivateKey(),
		serial: [UInt8] = [0x01, 0x02]
	) throws -> Data {
		try DCCSelfSignedCertificate.make(
			privateKey: key,
			serialNumber: serial,
			notBefore: notBefore,
			notAfter: notAfter
		)
	}

	@Test("Security parses the certificate and reads back its name, dates and key")
	func parses() throws {
		let key = P256.Signing.PrivateKey()
		let der = try Self.make(key: key)
		let certificate = try #require(SecCertificateCreateWithData(nil, der as CFData))

		#expect(SecCertificateCopySubjectSummary(certificate) as String? == DCCSelfSignedCertificate.commonName)
		#expect(SecCertificateCopyNotValidBeforeDate(certificate) as Date? == Self.notBefore)
		#expect(SecCertificateCopyNotValidAfterDate(certificate) as Date? == Self.notAfter)
		let publicKey = try #require(SecCertificateCopyKey(certificate))
		let publicBytes = try #require(SecKeyCopyExternalRepresentation(publicKey, nil) as Data?)
		#expect(publicBytes == key.publicKey.x963Representation)
	}

	@Test("The signature verifies over the to-be-signed bytes with the certified key")
	func signatureVerifies() throws {
		let der = try Self.make()
		let certificate = try #require(SecCertificateCreateWithData(nil, der as CFData))
		let publicKey = try #require(SecCertificateCopyKey(certificate))
		let parts = try #require(DERReader.children(ofSequence: der))
		#expect(parts.count == 3)
		let tbs = parts[0]
		let signature = try #require(DERReader.contents(of: parts[2]))
		#expect(signature.first == 0)

		var error: Unmanaged<CFError>?
		let verified = SecKeyVerifySignature(
			publicKey,
			.ecdsaSignatureMessageX962SHA256,
			tbs as CFData,
			signature.dropFirst() as CFData,
			&error
		)
		#expect(verified)
	}

	@Test("Security pairs the certificate with its private key")
	func identityPairs() throws {
		let key = P256.Signing.PrivateKey()
		let der = try Self.make(key: key)
		let certificate = try #require(SecCertificateCreateWithData(nil, der as CFData))
		let attributes: [CFString: Any] = [
			kSecAttrKeyType: kSecAttrKeyTypeECSECPrimeRandom,
			kSecAttrKeyClass: kSecAttrKeyClassPrivate,
		]
		let privateKey = try #require(SecKeyCreateWithData(
			key.x963Representation as CFData, attributes as CFDictionary, nil
		))
		#expect(SecIdentityCreate(nil, certificate, privateKey) != nil)
	}

	@Test("Serial numbers are encoded as positive minimal integers", arguments: [
		([0x00, 0x00, 0x05], [0x02, 0x01, 0x05]),
		([0x7F], [0x02, 0x01, 0x7F]),
		([0x80], [0x02, 0x02, 0x00, 0x80]),
		([0x00, 0xFF, 0x01], [0x02, 0x03, 0x00, 0xFF, 0x01]),
	] as [([UInt8], [UInt8])])
	func serialEncoding(magnitude: [UInt8], expected: [UInt8]) throws {
		#expect(DERWriter.integer(magnitude) == Data(expected))
		let der = try Self.make(serial: magnitude)
		let certificate = try #require(SecCertificateCreateWithData(nil, der as CFData))
		let serial = try #require(SecCertificateCopySerialNumberData(certificate, nil) as Data?)
		#expect(serial == Data(expected.dropFirst(2)))
	}

	@Test("A zero or oversized serial and an inverted validity period are refused")
	func refusals() {
		#expect(throws: DCCSelfSignedCertificate.BuildError.zeroSerialNumber) {
			try Self.make(serial: [0, 0])
		}
		#expect(throws: DCCSelfSignedCertificate.BuildError.oversizedSerialNumber) {
			try Self.make(serial: Array(repeating: 0x11, count: 21))
		}
		#expect(throws: DCCSelfSignedCertificate.BuildError.invalidValidityPeriod) {
			try DCCSelfSignedCertificate.make(
				privateKey: P256.Signing.PrivateKey(),
				serialNumber: [1],
				notBefore: Self.notAfter,
				notAfter: Self.notBefore
			)
		}
	}

	@Test("A random serial is sixteen octets and never zero")
	func randomSerial() {
		let serial = DCCSelfSignedCertificate.randomSerialNumber()
		#expect(serial.count == 16)
		#expect(serial.contains { $0 != 0 })
	}

	@Test("Times before 2050 are UTCTime and later ones GeneralizedTime")
	func timeEncoding() throws {
		let utc = try #require(TimeZone(identifier: "UTC"))
		let calendar = Calendar(identifier: .gregorian)
		let before = try #require(calendar.date(from: DateComponents(
			timeZone: utc, year: 2049, month: 12, day: 31, hour: 23, minute: 59, second: 58
		)))
		let after = try #require(calendar.date(from: DateComponents(
			timeZone: utc, year: 2050, month: 1, day: 2, hour: 3, minute: 4, second: 5
		)))

		#expect(DERWriter.time(before) == Data([0x17, 13]) + Data("491231235958Z".utf8))
		#expect(DERWriter.time(after) == Data([0x18, 15]) + Data("20500102030405Z".utf8))

		let der = try DCCSelfSignedCertificate.make(
			privateKey: P256.Signing.PrivateKey(), serialNumber: [1], notBefore: before, notAfter: after
		)
		let certificate = try #require(SecCertificateCreateWithData(nil, der as CFData))
		#expect(SecCertificateCopyNotValidAfterDate(certificate) as Date? == after)
	}

	@Test("The certificate carries basic constraints, key usage and both extended key usages")
	func extensions() throws {
		let der = try Self.make()
		let expected: [[UInt8]] = [
			// basicConstraints, critical, CA:FALSE
			[0x06, 0x03, 0x55, 0x1D, 0x13, 0x01, 0x01, 0xFF, 0x04, 0x02, 0x30, 0x00],
			// keyUsage, critical, digitalSignature
			[0x06, 0x03, 0x55, 0x1D, 0x0F, 0x01, 0x01, 0xFF, 0x04, 0x04, 0x03, 0x02, 0x07, 0x80],
			// serverAuth and clientAuth
			[0x06, 0x08, 0x2B, 0x06, 0x01, 0x05, 0x05, 0x07, 0x03, 0x01],
			[0x06, 0x08, 0x2B, 0x06, 0x01, 0x05, 0x05, 0x07, 0x03, 0x02],
		]
		for bytes in expected {
			#expect(der.range(of: Data(bytes)) != nil)
		}
	}

	@Test("Long elements use the long length form")
	func longLength() {
		let encoded = DERWriter.octetString(Data(repeating: 0xAB, count: 300))
		#expect(encoded.prefix(4) == Data([0x04, 0x82, 0x01, 0x2C]))
		#expect(encoded.count == 304)
	}
}

/// Just enough DER reading to take a certificate apart in tests.
enum DERReader {
	/// The complete elements directly inside a SEQUENCE.
	static func children(ofSequence der: Data) -> [Data]? {
		guard let contents = contents(of: der) else { return nil }
		var elements: [Data] = []
		var index = contents.startIndex
		while index < contents.endIndex {
			guard let (headerLength, bodyLength) = header(contents, at: index) else { return nil }
			let end = index + headerLength + bodyLength
			guard end <= contents.endIndex else { return nil }
			elements.append(Data(contents[index ..< end]))
			index = end
		}
		return elements
	}

	/// The value bytes of one element.
	static func contents(of element: Data) -> Data? {
		guard let (headerLength, bodyLength) = header(element, at: element.startIndex),
		      element.count == headerLength + bodyLength
		else { return nil }
		return Data(element.dropFirst(headerLength))
	}

	private static func header(_ data: Data, at index: Data.Index) -> (Int, Int)? {
		guard index + 1 < data.endIndex else { return nil }
		let first = data[index + 1]
		guard first & 0x80 != 0 else { return (2, Int(first)) }
		let count = Int(first & 0x7F)
		guard count > 0, count <= 4, index + 1 + count < data.endIndex else { return nil }
		let length = data[(index + 2) ..< (index + 2 + count)].reduce(0) { $0 << 8 | Int($1) }
		return (2 + count, length)
	}
}
