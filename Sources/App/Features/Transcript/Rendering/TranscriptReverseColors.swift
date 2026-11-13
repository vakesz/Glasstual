// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

// AppKit: the swap is made between two `NSColor` values already resolved
// against the theme.
import AppKit

/** The colours of a run the reverse control code (`0x16`) applies to.

 Reverse swaps what the text is drawn in with what it is drawn on. A run that
 names no background is drawn on the ground its line sits on, so that ground is
 what the text takes: the caller resolves both ends against the theme and the
 appearance first, which keeps the swap right in light, dark, increased
 contrast and print. */
struct TranscriptReverseColors: Equatable {
	var foreground: NSColor
	/// `nil` where the run is drawn on nothing of its own.
	var background: NSColor?

	/// The colours as drawn: swapped for a reversed run, otherwise as given.
	/// `fallbackBackground` stands in for the ground a run without a
	/// background of its own sits on.
	static func resolve(
		foreground: NSColor,
		background: NSColor?,
		isReversed: Bool,
		fallbackBackground: NSColor
	) -> Self {
		guard isReversed else { return Self(foreground: foreground, background: background) }
		return Self(foreground: background ?? fallbackBackground, background: foreground)
	}
}
