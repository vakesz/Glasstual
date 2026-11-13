// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import CryptoKit
import Foundation
import Testing

@Suite("Data digests and addresses")
@MainActor
struct DataExtensionsTests {
	@Test("Digests render as lowercase hex of the published length")
	func digestsRenderAsHex() {
		let source = Data("abc".utf8) as NSData

		#expect(source.sha1Hex == "a9993e364706816aba3e25717850c26c9cd0d89d")
		#expect(source.sha256Hex == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
		#expect(source.sha512Hex == "ddaf35a193617abacc417349ae204131" +
			"12e6fa4e89a97ea20a9eeee64b55d39a" +
			"2192992a274fc1a836ba3c23a3feebbd" +
			"454d4423643ce80e2a9ac94fa54ca49f")
	}

	/// `inet_ntop` reads four or sixteen bytes for the family it is handed and
	/// cannot be told how many are there, so anything else has to be refused
	/// before it reads past the end of the data.
	@Test("An address is presented only from exactly the bytes its family has")
	func addressesRequireTheirExactByteCount() {
		#expect(Data([127, 0, 0, 1]).IPv4Address == "127.0.0.1")
		#expect(Data().IPv4Address == nil)
		#expect(Data([127, 0, 0]).IPv4Address == nil)
		#expect(Data([127, 0, 0, 1, 1]).IPv4Address == nil)

		let loopback = Data([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1])

		#expect(loopback.IPv6Address == "::1")
		#expect(Data().IPv6Address == nil)
		#expect(loopback.dropLast().IPv6Address == nil)
		#expect((loopback + Data([0])).IPv6Address == nil)
		#expect(Data([127, 0, 0, 1]).IPv6Address == nil)
	}
}
