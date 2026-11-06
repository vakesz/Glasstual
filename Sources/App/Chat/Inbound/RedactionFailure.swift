// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/** Why a server refused a `REDACT`, from the code its `FAIL REDACT` carried.

 The codes belong to the draft/message-redaction specification. A code the
 build does not know keeps the server's own description, so a refusal is never
 reported as less than the server said. */
enum RedactionFailure: Equatable, Sendable {
	case forbidden
	case windowExpired
	case unknownMessage
	case invalidTarget
	case other(description: String)

	init(code: String, description: String) {
		self = switch code.uppercased() {
		case "REDACT_FORBIDDEN": .forbidden
		case "REDACT_WINDOW_EXPIRED": .windowExpired
		case "UNKNOWN_MSGID": .unknownMessage
		case "INVALID_TARGET": .invalidTarget
		default: .other(description: description)
		}
	}

	/// The explanation the reader sees, already localized.
	var explanation: String {
		switch self {
		case .forbidden: String(localized: .IRC.redactionForbidden)
		case .windowExpired: String(localized: .IRC.redactionWindowExpired)
		case .unknownMessage: String(localized: .IRC.redactionUnknownMessage)
		case .invalidTarget: String(localized: .IRC.redactionInvalidTarget)
		case let .other(description): description
		}
	}
}
