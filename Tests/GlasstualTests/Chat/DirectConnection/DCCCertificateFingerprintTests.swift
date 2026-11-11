// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CryptoKit
import Foundation
@testable import Glasstual
import Testing

@Suite("DCC certificate fingerprint")
struct DCCCertificateFingerprintTests {
	private nonisolated static let sequential = Data((0 ..< 32).map { UInt8($0) })
	private nonisolated static let sequentialText = (0 ..< 32).map { String(format: "%02X", $0) }.joined(separator: ":")

	@Test("The fingerprint is the SHA-256 of the DER")
	func digest() {
		let der = Data("certificate".utf8)
		#expect(DCCCertificateFingerprint(certificate: der).bytes == Data(SHA256.hash(data: der)))
	}

	@Test("Formatting is uppercase colon-separated octets in four lines of eight")
	func formatting() throws {
		let fingerprint = try #require(DCCCertificateFingerprint(userText: Self.sequentialText))
		#expect(fingerprint.bytes == Self.sequential)
		#expect(fingerprint.formatted == Self.sequentialText)
		#expect(fingerprint.grouped == [
			"00:01:02:03:04:05:06:07",
			"08:09:0A:0B:0C:0D:0E:0F",
			"10:11:12:13:14:15:16:17",
			"18:19:1A:1B:1C:1D:1E:1F",
		])
	}

	@Test("User text may use colons, spaces, dashes and either case", arguments: [
		sequentialText,
		sequentialText.lowercased(),
		sequentialText.replacingOccurrences(of: ":", with: " "),
		sequentialText.replacingOccurrences(of: ":", with: "-"),
		sequentialText.replacingOccurrences(of: ":", with: ""),
	])
	func parsesUserText(text: String) {
		#expect(DCCCertificateFingerprint(userText: text)?.bytes == Self.sequential)
	}

	@Test("Wrong lengths and non-hexadecimal text are refused", arguments: [
		"",
		"AB:CD",
		String(sequentialText.dropLast(3)),
		sequentialText + ":00",
		sequentialText.replacingOccurrences(of: "0A", with: "0G"),
		String(repeating: "١", count: 64),
	])
	func refusesBadText(text: String) {
		#expect(DCCCertificateFingerprint(userText: text) == nil)
	}

	@Test("Coding round-trips and refuses a digest of the wrong length")
	func coding() throws {
		let fingerprint = DCCCertificateFingerprint(certificate: Data("x".utf8))
		let encoded = try PropertyListEncoder().encode([fingerprint])
		#expect(try PropertyListDecoder().decode([DCCCertificateFingerprint].self, from: encoded) == [fingerprint])

		let short = try PropertyListEncoder().encode([Data([1, 2, 3])])
		#expect(throws: DecodingError.self) {
			try PropertyListDecoder().decode([DCCCertificateFingerprint].self, from: short)
		}
	}
}
