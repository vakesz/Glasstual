// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CryptoKit
import Foundation

/** The SHA-256 digest of a certificate's DER encoding.

 Secure DCC has no certificate authority, so this is the whole of a peer's
 identity: it is what a pin stores, what a prompt shows for comparison out of
 band, and what the user reads aloud to the person on the other end. */
nonisolated struct DCCCertificateFingerprint: Hashable, Codable, Sendable {
	static let byteCount = SHA256.byteCount

	let bytes: Data

	init(certificate der: Data) {
		bytes = Data(SHA256.hash(data: der))
	}

	/// Accepts the digest written with or without colons, spaces or dashes
	/// between octets, in either case. Anything that is not 32 octets of
	/// hexadecimal is refused.
	init?(userText: String) {
		let digits = userText.unicodeScalars.filter { [":", " ", "-", "\t"].contains($0) == false }
		guard digits.count == Self.byteCount * 2 else { return nil }

		var bytes = Data(capacity: Self.byteCount)
		var high: UInt8?
		for scalar in digits {
			guard scalar.isASCII, let nibble = UInt8(String(scalar), radix: 16) else { return nil }
			if let pending = high {
				bytes.append(pending << 4 | nibble)
				high = nil
			} else {
				high = nibble
			}
		}
		self.bytes = bytes
	}

	init(from decoder: any Decoder) throws {
		let bytes = try decoder.singleValueContainer().decode(Data.self)
		guard bytes.count == Self.byteCount else {
			throw DecodingError.dataCorrupted(.init(
				codingPath: decoder.codingPath,
				debugDescription: "A certificate fingerprint is \(Self.byteCount) bytes"
			))
		}
		self.bytes = bytes
	}

	func encode(to encoder: any Encoder) throws {
		var container = encoder.singleValueContainer()
		try container.encode(bytes)
	}

	/// Every octet in uppercase hexadecimal, separated by colons.
	var formatted: String {
		octets.joined(separator: ":")
	}

	/// The colon-separated form in four lines of eight octets, which is short
	/// enough to compare by eye.
	var grouped: [String] {
		stride(from: 0, to: octets.count, by: 8).map {
			octets[$0 ..< min($0 + 8, octets.count)].joined(separator: ":")
		}
	}

	private var octets: [String] {
		bytes.map { byte in
			let digits = String(byte, radix: 16, uppercase: true)
			return byte < 0x10 ? "0" + digits : digits
		}
	}
}
