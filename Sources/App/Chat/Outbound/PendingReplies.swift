// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

/// The `+draft/reply` target the next outgoing message, and the next printed line, carry.
struct PendingReplies {
	/// Set by the input field when the user replies to a message.
	var nextMessage: String?
	/// Set while the message carrying a reply is echoed into the transcript.
	var nextPrintedLine: String?

	mutating func takeForMessage() -> String? {
		defer { nextMessage = nil }
		return nextMessage
	}

	mutating func takeForPrintedLine() -> String? {
		defer { nextPrintedLine = nil }
		return nextPrintedLine
	}
}
