// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing

@MainActor
@Suite("IRC case folding")
struct IRCCaseFoldingTests {
	private nonisolated static let mappings: [ISupportCaseMapping] = [.rfc1459, .strictRFC1459, .ascii, .rfc7613]

	private static let samples = [
		"", "alice", "ALICE", "Alice[away]", "[A]\\\\b~C", "{a}|b^c", "~~", "Zoë", "ÀÉ[x]~", "🦊Fox", "a\\b", "MiXeD123_-",
	]

	@Test("Folding matches the previous scalar-by-scalar implementation", arguments: mappings)
	func foldingMatchesReference(mapping: ISupportCaseMapping) {
		for sample in Self.samples {
			#expect(IRCCaseFolding.fold(sample, using: mapping) == Self.reference(sample, mapping))
		}
	}

	@Test("RFC 1459 folds brackets, backslash and tilde; strict RFC 1459 keeps tilde")
	func bracketsAndTilde() {
		#expect(IRCCaseFolding.fold("[]\\~", using: .rfc1459) == "{}|^")
		#expect(IRCCaseFolding.fold("[]\\~", using: .strictRFC1459) == "{}|~")
		#expect(IRCCaseFolding.fold("[]\\~A", using: .ascii) == "[]\\~a")
	}

	private static func reference(_ string: String, _ caseMapping: ISupportCaseMapping) -> String {
		guard string.isEmpty == false else { return string }
		guard caseMapping != .rfc7613 else {
			return string.lowercased().precomposedStringWithCanonicalMapping
		}
		let scalars = string.unicodeScalars.map { scalar -> UnicodeScalar in
			let value = scalar.value
			if value >= 65, value <= 90, let lowercase = UnicodeScalar(value + 32) {
				return lowercase
			}
			guard caseMapping != .ascii else { return scalar }
			switch scalar {
			case "[": return "{"
			case "]": return "}"
			case "\\": return "|"
			case "~" where caseMapping == .rfc1459: return "^"
			default: return scalar
			}
		}
		return String(String.UnicodeScalarView(scalars))
	}
}
