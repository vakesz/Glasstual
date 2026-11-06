// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

@testable import Glasstual
import Testing

@MainActor
@Suite("Mask normalizer")
struct MaskNormalizerTests {
	@Test(
		"Typed text becomes the mask the list holds",
		arguments: [
			"troll": "troll!*@*",
			"  troll  ": "troll!*@*",
			"troll!ident": "troll!ident@*",
			"ident@host.example": "*!ident@host.example",
			"host.example": "*!*@host.example",
			"2001:db8::1": "*!*@2001:db8::1",
			"troll!ident@host.example": "troll!ident@host.example",
			"$a:account": "$a:account",
			"~a:account": "~a:account",
		]
	)
	func expands(input: String, expected: String) {
		#expect(MaskNormalizer.normalize(input) == .success(expected))
	}

	@Test("Text that cannot be one parameter is rejected")
	func rejects() {
		#expect(MaskNormalizer.normalize("   ") == .failure(.empty))
		#expect(MaskNormalizer.normalize("a b") == .failure(.containsWhitespace))
		#expect(MaskNormalizer.normalize(":nick") == .failure(.startsWithColon))
		#expect(MaskNormalizer.normalize(String(repeating: "a", count: 201)) == .failure(.tooLong))
	}
}
