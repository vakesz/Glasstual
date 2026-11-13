// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/** What a network lets one `draft/multiline` message hold.

 The server states the limits in the capability's value, as in
 `draft/multiline=max-bytes=4096,max-lines=100`. `max-bytes` is required: a
 value without it names no ceiling the client could stay under, so the
 capability is not usable and the text goes out line by line instead.
 `max-lines` is optional, and its absence means the server set no line limit. */
nonisolated struct MultilineLimits: Equatable, Sendable {
	static let capabilityName = "draft/multiline"
	/// The `BATCH` type a multi-line message travels in.
	static let batchType = "draft/multiline"
	/// The tag on a line that continues the one before it without a line break.
	static let concatTag = "draft/multiline-concat"

	let maximumBytes: Int
	/// `nil` when the server advertised no line limit.
	let maximumLines: Int?

	init(maximumBytes: Int, maximumLines: Int? = nil) {
		self.maximumBytes = maximumBytes
		self.maximumLines = maximumLines
	}

	/** The limits a capability value states, or `nil` when it cannot be used.

	 - Parameter values: The capability value split at its commas, the way the
	   registry keeps what `CAP LS` offered. */
	init?(capabilityValues values: [String]) {
		var bytes: Int?
		var lines: Int?

		for value in values {
			let parts = value.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)

			guard parts.count == 2, let number = Int(parts[1]), number > 0 else { continue }

			switch parts[0] {
			case "max-bytes": bytes = number
			case "max-lines": lines = number
			default: continue
			}
		}

		guard let bytes else { return nil }

		self.init(maximumBytes: bytes, maximumLines: lines)
	}
}
