// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
import Foundation

/** Draws wire text inside a directional isolate of its own, which bounds the
 reordering the implicit bidirectional algorithm still does.

 The transcript is one text storage. A paragraph that begins with a timestamp
 and a name looks exactly like a line someone else sent, so each piece of wire
 text is held inside an isolate and its control characters are settled first by
 ``ControlCharacterDisposition``. */
nonisolated enum TranscriptIsolate {
	/// U+2068 FIRST STRONG ISOLATE: opens the isolate a wire string is drawn in.
	static let isolateStart = "\u{2068}"
	/// U+2069 POP DIRECTIONAL ISOLATE: closes it.
	static let isolateEnd = "\u{2069}"

	/** Appends `text` inside a directional isolate, so its own reading order
	 cannot reorder whatever is drawn beside it.

	 The isolate characters carry the surrounding run's attributes, minus the
	 ones that would make them clickable, and are marked as the transcript's own
	 padding so that copying leaves them out. */
	static func appendIsolated(
		_ text: NSAttributedString,
		to result: NSMutableAttributedString,
		isolateAttributes: [NSAttributedString.Key: Any]
	) {
		guard text.length > 0 else { return }
		var attributes = isolateAttributes
		attributes.removeValue(forKey: .transcriptAction)
		attributes.removeValue(forKey: .transcriptReaction)
		attributes.removeValue(forKey: .link)
		attributes[.transcriptPadding] = true
		result.append(NSAttributedString(string: isolateStart, attributes: attributes))
		result.append(text)
		result.append(NSAttributedString(string: isolateEnd, attributes: attributes))
	}
}
