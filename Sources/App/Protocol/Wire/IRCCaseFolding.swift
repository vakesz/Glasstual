// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/** Folding a name to the form the server compares it in.

 Which spellings of a nickname or a channel name are the same name is the
 server's `CASEMAPPING` to decide, and everything that compares one — the
 member list, the address book, the transcript's nickname colouring — has to
 ask the same question the same way. */
nonisolated enum IRCCaseFolding {
	static func fold(_ string: String, using caseMapping: ISupportCaseMapping) -> String {
		guard string.isEmpty == false else {
			return string
		}

		guard caseMapping != .rfc7613 else {
			/* RFC 7613 §3.3 (UsernameCaseMapped): lowercase the whole string
			 under Unicode's rules, then normalise to NFC, so two spellings of
			 the same name compare equal. None of the RFC 1459 punctuation
			 equivalences apply — "[Alice]" and "{alice}" are different people. */
			return string.lowercased().precomposedStringWithCanonicalMapping
		}

		let scalars = string.unicodeScalars.map { scalar -> UnicodeScalar in
			let value = scalar.value

			if value >= 65, value <= 90, let lowercase = UnicodeScalar(value + 32) {
				return lowercase
			}

			guard caseMapping != .ascii else {
				return scalar
			}

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
