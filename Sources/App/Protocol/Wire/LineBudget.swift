// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/** How many bytes of one IRC line are left.

 An IRC line is capped in **bytes**, not characters: 512 including the CR LF,
 or whatever `LINELEN` raises that to. The framing the server prepends — the
 sender's hostmask, the command, the target, the separators — is charged before
 any of the message body is, so what the body actually gets is the difference.

 The arithmetic is signed on purpose. A server-assigned hostmask plus a long
 channel name can make the framing alone longer than the whole line, and the
 unsigned subtraction that used to compute the remainder wrapped that case into
 a budget of four billion bytes. Here it simply reads as exhausted. */
nonisolated struct LineBudget: Equatable, Sendable {
	/// What the wire framing costs before the body starts.
	let overhead: Int

	/// The longest line, in bytes, the server accepts.
	let maximum: Int

	/// Bytes charged so far, framing included.
	private(set) var used: Int

	init(overhead: Int, maximum: Int) {
		self.overhead = max(overhead, 0)
		self.maximum = max(maximum, 0)
		used = self.overhead
	}

	/// `true` once nothing more fits — including when the framing alone
	/// already overran the line.
	var isOverBudget: Bool {
		used > maximum
	}

	/// The bytes still available. Never negative.
	var remaining: Int {
		max(maximum - used, 0)
	}

	/// Whether `byteCount` more bytes would still fit.
	func fits(_ byteCount: Int) -> Bool {
		used + max(byteCount, 0) <= maximum
	}

	/// Charges `byteCount` bytes against the line. A negative count is ignored
	/// rather than refunding bytes that were never spent.
	mutating func charge(_ byteCount: Int) {
		used += max(byteCount, 0)
	}
}
