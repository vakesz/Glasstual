// Copyright (c) 2018 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/** The ceiling was passed before a terminator arrived.

 The lines completed before that are the peer's, and the caller may still hand
 them on ahead of failing the connection: everything after the overrun on the
 same read is dropped, because the stream is no longer trustworthy. */
nonisolated struct LineFramingError: Error {
	let completedLines: [Data]
}

/** Cuts a byte stream into newline-terminated lines.

 Both processes frame the same way — an IRC connection in the host and a DCC
 CHAT connection in the app — so the framing lives here and each side says how
 its protocol spells a line ending.

 Terminators are found a line at a time rather than a byte at a time, and the
 common case — a read that carries whole lines and nothing was left over —
 hands each line straight out of the read without touching the buffer at all.
 Only a partial line is copied, and only once: the buffer keeps its allocation
 across lines and is never rescanned. Removing each line from the front of the
 buffer as it was found moved everything behind it every time, which made a
 read carrying many short lines cost the square of its length.

 A peer that never sends a terminator must not be able to grow the buffer
 without bound, so buffering past ``maximumLineLength`` throws rather than
 continuing; memory is bounded by the ceiling plus one read. */
nonisolated struct LineFramer {
	/// Maximum bytes held while waiting for a terminator.
	let maximumLineLength: Int

	/** Whether a CR before the line feed belongs to the terminator.

	 Every CR at the end of an IRC line belongs to the terminator, not to the
	 line. A server whose MOTD file has CRLF line endings writes each of those
	 lines as `CR CR LF`, so stripping a single CR left one on the end of the
	 trailing parameter, where nothing downstream may carry it: it reached the
	 transcript as an invisible control character on every line of the MOTD.
	 DCC CHAT leaves the CR on the line and the direct-chat reader strips it
	 when it decodes. */
	let stripsCarriageReturns: Bool

	/// Whether a line with nothing left in it is dropped rather than emitted.
	let dropsEmptyLines: Bool

	/// Bytes after the last terminator, waiting for the rest of their line.
	private var pending = Data()

	init(maximumLineLength: Int, stripsCarriageReturns: Bool, dropsEmptyLines: Bool) {
		self.maximumLineLength = maximumLineLength
		self.stripsCarriageReturns = stripsCarriageReturns
		self.dropsEmptyLines = dropsEmptyLines
	}

	/// Whether part of a line is waiting for the read that completes it.
	var hasPartialLine: Bool {
		pending.isEmpty == false
	}

	/// Forgets whatever is buffered, for a connection starting over.
	mutating func reset() {
		pending.removeAll()
	}

	/// The lines `payload` completes, in order.
	mutating func lines(appending payload: Data) throws(LineFramingError) -> [Data] {
		var lines: [Data] = []
		var remaining = payload[...]

		while let terminator = remaining.firstIndex(of: 0x0A) {
			let line = remaining[..<terminator]
			remaining = remaining[remaining.index(after: terminator)...]

			guard pending.isEmpty == false else {
				/* A whole line inside one read, handed out without a copy into
				 the buffer. A read is bounded well under the line ceiling. */
				append(line, to: &lines)

				continue
			}

			guard buffer(line) else {
				throw LineFramingError(completedLines: lines)
			}

			append(pending[...], to: &lines)
			pending.removeAll(keepingCapacity: true)
		}

		if remaining.isEmpty == false, buffer(remaining) == false {
			throw LineFramingError(completedLines: lines)
		}

		return lines
	}

	/// Appends `line` as this protocol spells it: terminator remnants off, and
	/// nothing at all when the protocol has no use for an empty line.
	private func append(_ line: Data.SubSequence, to lines: inout [Data]) {
		var trimmed = line

		if stripsCarriageReturns {
			while trimmed.last == 0x0D {
				trimmed = trimmed.dropLast()
			}
		}

		guard trimmed.isEmpty == false || dropsEmptyLines == false else {
			return
		}

		lines.append(Data(trimmed))
	}

	/// Holds `bytes` until the rest of their line arrives, reporting whether
	/// the line is still inside the ceiling.
	private mutating func buffer(_ bytes: Data.SubSequence) -> Bool {
		guard pending.count + bytes.count <= maximumLineLength else {
			return false
		}

		pending.append(contentsOf: bytes)

		return true
	}
}
