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

nonisolated enum IRCProtocolLimits { // nonisolated: value
	static let maximumBodyLength = 510
	static let maximumNodesPerModeCommand = 4
	static let defaultNicknameMaximumLength = 31
	/** The largest `LINELEN` worth believing.

	 IRCv3 raises the RFC 1459 line length, but only to a few times it. A larger
	 advertised value stops the client splitting outgoing lines at all, so it is
	 clamped rather than trusted. */
	static let maximumServerLineLength = maximumBodyLength * 4
	/// The CR LF every line ends with. `LINELEN` counts it; ``maximumBodyLength``
	/// does not, which is the whole reason the two differ by this much.
	static let lineTerminatorLength = 2
	/// RFC 1459 2.3 caps a command at fifteen parameters, and a server that
	/// reads a sixteenth folds the rest into the fifteenth. This is the cap the
	/// client writes to; see ``maximumInboundParameterCount`` for what it reads.
	static let maximumParameterCount = 15
	/** How many parameters one inbound line is split into.

	 Deliberately looser than ``maximumParameterCount``: what the client sends
	 has to be a line every server will accept, but what it reads only has to be
	 bounded. Servers do exceed the RFC — a long `RPL_ISUPPORT` or a vendor
	 numeric counts parameters its own way — and dropping the tail of one would
	 lose information the client was told. Sixty-four leaves room for those
	 while still bounding what a hostile line can allocate; anything past the cap
	 is handed to the last parameter as one string rather than dropped. */
	static let maximumInboundParameterCount = 64
	/** How many bytes the message-tag section of a client-to-server line gets.

	 IRCv3 budgets tags separately from the rest of the line — 4096 bytes for
	 what the client sends, including the leading `@` and the space that ends
	 the section — so a tagged line is measured as two budgets, not one. */
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
	   ``IRCJoinBatching`` and the outbound parameter budget size their lines
	   from, because a line cut to 510 on a server that carries 1024 loses text
	   the server would have taken. */
	static func enforcedWireLine(_ line: String, bodyLimit: Int = maximumBodyLength) -> String {
		let bodyLimit = max(bodyLimit, 1)

		guard let tagSectionEnd = tagSectionEnd(of: line) else {
			return ClientWireUtilities.truncated(line, toByteCount: bodyLimit)
		}

		let tagSection = String(line[line.startIndex ..< tagSectionEnd])
		let body = String(line[tagSectionEnd...])

		return enforcedTagSection(tagSection)
			+ ClientWireUtilities.truncated(body, toByteCount: bodyLimit)
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
}
