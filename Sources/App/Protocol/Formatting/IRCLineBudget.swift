/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 *
 *  * Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 *  * Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 *  * Neither the name of Textual, "Codeux Software, LLC", nor the
 *    names of its contributors may be used to endorse or promote products
 *    derived from this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED. IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
 * FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
 * OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
 * LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
 * OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
 * SUCH DAMAGE.
 *
 *********************************************************************** */

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
nonisolated struct IRCLineBudget: Equatable, Sendable { // nonisolated: value
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
