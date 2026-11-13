// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/** How a highlighted message is told apart without its colour.

 The highlight colours are one cue among several. A reader who has asked to
 differentiate without colour gets an underline in the highlight's own text
 colour, and a reader who is not looking hears the word first. */
nonisolated enum TranscriptHighlightCue {
	/// Whether a highlighted run is underlined. Every highlighted run is: a
	/// run that carries an action is drawn in the highlight's colours like the
	/// text around it, so nothing else sets it apart.
	nonisolated static func underlinesRun( // nonisolated: pure
		isHighlighted: Bool,
		differentiatesWithoutColor: Bool
	) -> Bool {
		isHighlighted && differentiatesWithoutColor
	}

	/** Whether a run's action chooses the colour of its text.

	 A link, a channel and a nickname each have a colour picked to be read on
	 the transcript's ground. A highlighted run is drawn on the highlight's
	 ground instead, and the only colour measured against that is the
	 highlight's own text role: a pale nickname on the yellow of a dark-mode
	 highlight cannot be read. The action stays; its colour gives way. */
	nonisolated static func actionColorsRun(isHighlighted: Bool) -> Bool { // nonisolated: pure
		isHighlighted == false
	}

	/// The spoken text of a highlighted line's first run: the highlight word
	/// ahead of whatever that run already says.
	nonisolated static func spokenText(prefix: String, existing: [String]) -> [String] { // nonisolated: pure
		existing.first == prefix ? existing : [prefix] + existing
	}
}
