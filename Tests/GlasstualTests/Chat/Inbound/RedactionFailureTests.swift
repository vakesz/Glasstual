// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing

@MainActor
@Suite("Redaction failure codes")
struct RedactionFailureTests {
	@Test("The codes the specification defines map to their cases", arguments: [
		("REDACT_FORBIDDEN", RedactionFailure.forbidden),
		("REDACT_WINDOW_EXPIRED", .windowExpired),
		("UNKNOWN_MSGID", .unknownMessage),
		("INVALID_TARGET", .invalidTarget),
		("redact_forbidden", .forbidden),
	])
	func knownCodes(code: String, expected: RedactionFailure) {
		#expect(RedactionFailure(code: code, description: "ignored") == expected)
	}

	@Test("An unknown code keeps the server's own words")
	func unknownCodeKeepsTheDescription() {
		let failure = RedactionFailure(code: "SOMETHING_NEW", description: "Try later")

		#expect(failure == .other(description: "Try later"))
		#expect(failure.explanation == "Try later")
	}

	@Test("A known code is explained in the reader's language, not the server's")
	func knownCodeIsLocalized() {
		#expect(RedactionFailure.forbidden.explanation.isEmpty == false)
		#expect(RedactionFailure(code: "REDACT_FORBIDDEN", description: "nope").explanation != "nope")
	}
}
