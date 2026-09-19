// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/** How long the server said a value may be, against how much of it is used.

 TOPICLEN, KEYLEN and the rest are octet counts, so everything here is measured
 in UTF-8 bytes rather than in characters. Building one is failable because a
 server that advertised no limit has none to measure against, and a guessed
 number would be worse than saying nothing: the sheets that show a count show
 nothing at all until a connection names one. */
struct ServerLengthLimit: Equatable, Sendable {
	/// How many octets the value takes.
	let used: Int
	/// How many octets the server accepts.
	let maximum: Int

	/// `nil` when the server named no limit, which ISUPPORT spells as zero.
	init?(using value: String, maximum: UInt) {
		let limit = Int(clamping: maximum)
		guard limit > 0 else { return nil }

		used = value.utf8.count
		self.maximum = limit
	}

	/// What is left of the limit, negative once the value no longer fits -- which
	/// is what turns a count into a warning and disables the sheet's button.
	var remaining: Int {
		maximum - used
	}

	var isExceeded: Bool {
		used > maximum
	}
}
