// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/// One `PRIVMSG` or `NOTICE` inside a multi-line batch.
nonisolated struct MultilineWireLine: Equatable, Sendable {
	let text: String
	/// Whether the line carries `draft/multiline-concat`: it continues the
	/// line before it with no line break between them. The lines of one long
	/// line are cut by the byte budget, and this is how the server joins them.
	let continuesPrevious: Bool
}

/** The arithmetic of sending text as one `draft/multiline` batch.

 Pure decisions over lines that are already cut to the wire budget: whether
 they fit what the server advertised, which part to keep when they do not, and
 what the receiver will read them as. Cutting the lines is the session's
 job, because it needs the target and the connection's line budget. */
nonisolated enum MultilineBatchPlanner {
	/// Whether a set of lines is within the server's limits, and if not, which
	/// limit it is over. Lines are reported first when both are exceeded.
	enum Fit: Equatable, Sendable {
		case fits
		case tooManyLines
		case tooManyBytes
	}

	/** The bytes the lines add up to once joined.

	 Each line break between two logical lines counts as one byte. The server
	 counts payloads and may or may not count the breaks; counting them stays
	 under the limit either way. */
	static func payloadByteCount(of lines: [MultilineWireLine]) -> Int {
		var total = 0

		for (index, line) in lines.enumerated() {
			total += line.text.utf8.count

			if index > 0, line.continuesPrevious == false {
				total += 1
			}
		}

		return total
	}

	/// The text the receiver reads: lines joined by a line break, except a
	/// continuation, which joins with nothing.
	static func joinedText(of lines: [MultilineWireLine]) -> String {
		var result = ""

		for (index, line) in lines.enumerated() {
			if index > 0, line.continuesPrevious == false {
				result.append("\n")
			}

			result.append(line.text)
		}

		return result
	}

	/// How many lines the receiver sees: continuations belong to the line
	/// before them.
	static func logicalLineCount(of lines: [MultilineWireLine]) -> Int {
		lines.filter { $0.continuesPrevious == false }.count
	}

	static func fit(of lines: [MultilineWireLine], within limits: MultilineLimits) -> Fit {
		if let maximumLines = limits.maximumLines, lines.count > maximumLines {
			return .tooManyLines
		}

		return payloadByteCount(of: lines) > limits.maximumBytes ? .tooManyBytes : .fits
	}

	/** The lines without blank ones at either end.

	 Pasted text often carries a trailing line break or a blank line before the
	 first word. A message that opens or closes on nothing is not what was
	 meant, and a batch of only blank lines is refused by servers. */
	static func trimmingBlankEdges(_ lines: [MultilineWireLine]) -> [MultilineWireLine] {
		var result = lines[...]

		while let first = result.first, first.text.isEmpty {
			result = result.dropFirst()
		}

		while let last = result.last, last.text.isEmpty {
			result = result.dropLast()
		}

		return Array(result)
	}

	/** The longest start of `lines` that fits `limits`.

	 It ends on a whole line when it can: a line cut into several wire lines is
	 kept all together or dropped, so the text never stops mid-sentence unless
	 its first line alone is too long. */
	static func truncated(_ lines: [MultilineWireLine], to limits: MultilineLimits) -> [MultilineWireLine] {
		var kept: [MultilineWireLine] = []
		var bytes = 0

		for line in lines {
			let added = line.text.utf8.count + (kept.isEmpty || line.continuesPrevious ? 0 : 1)

			if let maximumLines = limits.maximumLines, kept.count + 1 > maximumLines {
				break
			}

			if bytes + added > limits.maximumBytes {
				break
			}

			kept.append(line)
			bytes += added
		}

		if kept.count < lines.count, lines[kept.count].continuesPrevious,
		   let lastWhole = kept.lastIndex(where: { $0.continuesPrevious == false }), lastWhole > 0
		{
			kept.removeSubrange(lastWhole...)
		}

		return trimmingBlankEdges(kept)
	}
}
