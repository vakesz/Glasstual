// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/** How a highlighted message is told apart without its colour.

 The highlight colours are one cue among several. A reader who has asked to
 differentiate without colour gets an underline in the highlight's own text
 colour, and a reader who is not looking hears the word first. */
nonisolated enum TranscriptHighlightCue {
	/// Whether a highlighted run is underlined. Runs that carry an action keep
	/// the styling of that action, which already sets them apart from the text
	/// around them.
	nonisolated static func underlinesRun( // nonisolated: pure
		isHighlighted: Bool,
		differentiatesWithoutColor: Bool,
		action: TranscriptRunAction?
	) -> Bool {
		isHighlighted && differentiatesWithoutColor && action == nil
	}

	/// The spoken text of a highlighted line's first run: the highlight word
	/// ahead of whatever that run already says.
	nonisolated static func spokenText(prefix: String, existing: [String]) -> [String] { // nonisolated: pure
		existing.first == prefix ? existing : [prefix] + existing
	}
}
