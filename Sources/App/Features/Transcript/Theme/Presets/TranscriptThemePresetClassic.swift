// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/** The palette Glasstual shipped as its default before the default followed
 the system colours, kept as the Classic preset.

 Every role carries a second pair for the system's Increase Contrast
 setting. Those are not a darker shade for its own sake: each was picked to
 clear 7:1 against the ground it is drawn on — the WCAG AAA minimum, one
 step above the 4.5:1 the ordinary pair holds — and the dark ground itself
 drops to black so the whole transcript gains from it.
 `ThemePaletteContrastTests` holds both floors. */
nonisolated extension TranscriptThemePalette {
	static let classic = TranscriptThemePalette(
		background: TranscriptTheme.pair(light: 0xFFFFFF, dark: 0x1E1E1E, contrastLight: 0xFFFFFF, contrastDark: 0x000000),
		primaryText: TranscriptTheme.pair(light: 0x202124, dark: 0xF2F2F2, contrastLight: 0x000000, contrastDark: 0xFFFFFF),
		secondaryText: TranscriptTheme.pair(light: 0x5F5F64, dark: 0xC2C2C6, contrastLight: 0x3A3A3C, contrastDark: 0xEBEBEF),
		/* A role of its own, added with the native transcript: timestamps used
			to be drawn in `secondaryText`. These are deliberately a step quieter
			than that — a timestamp is the least of what a line says — but the
			text also sits on the bubble grounds, and the quietest ground is the
			dark outgoing bubble, so the floor is the 4.5:1 the WCAG AA contrast
			minimum asks of body text, which this is a point smaller than, measured
			there: 4.59:1. The increased-contrast pair gives up that quietness,
			which is the whole point of the setting. */
		timestampText: TranscriptTheme.pair(light: 0x68686D, dark: 0xB6B6B9, contrastLight: 0x3A3A3C, contrastDark: 0xEBEBEF),
		eventText: TranscriptTheme.pair(light: 0x65656A, dark: 0xB6B6B9, contrastLight: 0x2C2C2E, contrastDark: 0xEBEBF0),
		link: TranscriptTheme.pair(light: 0x0065D2, dark: 0x81B9FF, contrastLight: 0x003E9C, contrastDark: 0xDEEDFF),
		localNickname: TranscriptTheme.pair(light: 0x006B3C, dark: 0x67D99A, contrastLight: 0x004F2B, contrastDark: 0xC4F7DA),
		remoteNickname: TranscriptTheme.pair(light: 0x5B42A6, dark: 0xBCAAFF, contrastLight: 0x3B2A80, contrastDark: 0xEEE9FF),
		highlightBackground: TranscriptTheme.pair(
			light: 0xFFF1B8, dark: 0x5C4710, contrastLight: 0xFFE066, contrastDark: 0x634A00
		),
		highlightText: TranscriptTheme.pair(light: 0x202124, dark: 0xFFFFFF, contrastLight: 0x000000, contrastDark: 0xFFFFFF),
		bubbleIncoming: TranscriptTheme.pair(light: 0xE9E9EB, dark: 0x363638, contrastLight: 0xDCDCDE, contrastDark: 0x48484A),
		bubbleOutgoing: TranscriptTheme.pair(light: 0xD8ECFF, dark: 0x164A73, contrastLight: 0xC3E1FF, contrastDark: 0x1A5080),
		unreadMarker: TranscriptTheme.pair(light: 0xD70015, dark: 0xFF6961, contrastLight: 0xA30010, contrastDark: 0xFF8A80),
		failure: TranscriptTheme.pair(light: 0xB00020, dark: 0xFF9A92, contrastLight: 0x8B0016, contrastDark: 0xFFE6E4),
		chromeBackground: TranscriptTheme.pair(light: 0xFFFFFF, dark: 0x1E1E1E, contrastLight: 0xFFFFFF, contrastDark: 0x000000)
	)
}
