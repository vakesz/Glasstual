// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing

@MainActor
@Suite("Client encoding and filtering policies")
struct ClientEncodingFilteringTests {
	@Test("A UTF-8 only network overrides both configured encodings")
	func utf8OnlyOverridesConfiguredEncodings() {
		let policy = TextEncodingPolicy(
			primary: .ascii,
			fallback: .isoLatin1,
			requiresUTF8: true
		)

		#expect(policy.primary == .utf8)
		#expect(policy.fallback == .utf8)
	}

	@Test("Encoding falls back to the lossless encoding rather than mangling the text")
	func encodingFallsBackWithoutLossBeforeASCII() {
		let policy = TextEncodingPolicy(
			primary: .ascii,
			fallback: .utf8,
			requiresUTF8: false
		)

		#expect(policy.encode("árvíz") == Data("árvíz".utf8))
	}

	@Test("Arbitrary bytes decode through Latin-1 rather than failing")
	func decodingFallsBackToLatin1ForArbitraryBytes() {
		let policy = TextEncodingPolicy(
			primary: .utf8,
			fallback: .ascii,
			requiresUTF8: false
		)

		#expect(policy.decode(Data([0xFF])) == "ÿ")
	}

	@Test("A lookup derives the tracking hostmask and both cache keys")
	func addressBookLookupDerivesTrackingHostmaskAndCacheKeys() {
		#expect(AddressBookLookupPolicy.trackingHostmask(forNickname: "Alice") == "Alice!*@*")
		#expect(
			AddressBookLookupPolicy.cacheKeys(forHostmask: "Alice!user@example.com") ==
				["Alice!user@example.com", "Alice!*@*"]
		)
	}
}
