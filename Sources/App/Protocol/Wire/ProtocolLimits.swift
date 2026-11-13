// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation

nonisolated enum ProtocolLimits {
	static let maximumBodyLength = 510
	static let maximumNodesPerModeCommand = 4
	static let defaultNicknameMaximumLength = 31
	/** The largest `LINELEN` worth believing.

	 IRCv3 raises the RFC 1459 line length, but only to a few times it. A larger
	 advertised value stops the session splitting outgoing lines at all, so it is
	 clamped rather than trusted. */
	static let maximumServerLineLength = maximumBodyLength * 4
	/// The CR LF every line ends with. `LINELEN` counts it; ``maximumBodyLength``
	/// does not, which is the whole reason the two differ by this much.
	static let lineTerminatorLength = 2
	/// RFC 1459 2.3 caps a command at fifteen parameters, and a server that
	/// reads a sixteenth folds the rest into the fifteenth. This is the cap the
	/// session writes to; see ``maximumInboundParameterCount`` for what it reads.
	static let maximumParameterCount = 15
	/** How many parameters one inbound line is split into.

	 Deliberately looser than ``maximumParameterCount``: what the session sends
	 has to be a line every server will accept, but what it reads only has to be
	 bounded. Servers do exceed the RFC — a long `RPL_ISUPPORT` or a vendor
	 numeric counts parameters its own way — and dropping the tail of one would
	 lose information the session was told. Sixty-four leaves room for those
	 while still bounding what a hostile line can allocate; anything past the cap
	 is handed to the last parameter as one string rather than dropped. */
	static let maximumInboundParameterCount = 64
	/** How many bytes the message-tag section of a client-to-server line gets.

	 IRCv3 budgets tags separately from the rest of the line, so a tagged line
	 is measured as two budgets, not one. A session may send 4094 bytes of tag
	 data; with the leading `@` and the space that ends the section, which is
	 what this measures, that is 4096. */
	static let maximumClientTagLength = 4096

	/** `line` cut down to what the protocol actually carries.

	 The tag section and the body are two budgets: tags are dropped whole from
	 the end rather than cut in half, because half a tag is not a tag, and the
	 body is cut at a character boundary. Returns `line` unchanged when it
	 already fits, so a caller can compare the two to tell whether anything was
	 lost.

	 - Parameter bodyLimit: How many bytes the command and its parameters get.
	   `LINELEN` less its CR LF where the server advertised one, and the RFC's
	   ``maximumBodyLength`` where it did not — the same figure
	   ``JoinBatching`` and the outbound parameter budget size their lines
	   from, because a line cut to 510 on a server that carries 1024 loses text
	   the server would have taken. */
	static func enforcedWireLine(_ line: String, bodyLimit: Int = maximumBodyLength) -> String {
		let bodyLimit = max(bodyLimit, 1)

		guard let tagSectionEnd = tagSectionEnd(of: line) else {
			return truncated(line, toByteCount: bodyLimit)
		}

		let tagSection = String(line[line.startIndex ..< tagSectionEnd])
		let body = String(line[tagSectionEnd...])

		return enforcedTagSection(tagSection)
			+ truncated(body, toByteCount: bodyLimit)
	}

	/// The body budget a server advertising `maximumLineLength` leaves, where
	/// zero or a nonsensical value means it advertised none.
	static func bodyLimit(forAdvertisedLineLength maximumLineLength: Int) -> Int {
		guard maximumLineLength > lineTerminatorLength else {
			return maximumBodyLength
		}

		return min(maximumLineLength, maximumServerLineLength) - lineTerminatorLength
	}

	/// The index one past the space that closes the `@`-prefixed tag section,
	/// or `nil` when the line carries no tags.
	private static func tagSectionEnd(of line: String) -> String.Index? {
		guard line.hasPrefix("@"), let separator = line.firstIndex(of: " ") else {
			return nil
		}

		return line.index(after: separator)
	}

	/// `tagSection` — `@`, the tags, and the trailing space — reduced to whole
	/// tags that fit the tag budget. An oversized single tag leaves nothing.
	private static func enforcedTagSection(_ tagSection: String) -> String {
		guard tagSection.utf8.count > maximumClientTagLength else {
			return tagSection
		}

		var tags = tagSection.dropFirst().dropLast().components(separatedBy: ";")

		while tags.isEmpty == false {
			let candidate = "@" + tags.joined(separator: ";") + " "

			if candidate.utf8.count <= maximumClientTagLength {
				return candidate
			}

			tags.removeLast()
		}

		return ""
	}

	/// `text` cut to at most `maximumByteCount` UTF-8 bytes without splitting a
	/// character. Zero means the server named no limit, which leaves the text
	/// alone: every ISUPPORT byte budget spells "unlimited" that way.
	static func truncated(_ text: String, toByteCount maximumByteCount: Int) -> String {
		guard maximumByteCount > 0 else {
			return text
		}

		return text.truncated(toUTF8Bytes: maximumByteCount)
	}
}
