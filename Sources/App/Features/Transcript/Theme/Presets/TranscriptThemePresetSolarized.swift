// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/** The Solarized palette by Ethan Schoonover, carrying its designed pair:
 cream grounds with slate text in light mode, deep blue grounds with
 gray-green text in dark mode.

 Solarized's charm is its low-contrast mid-tones, which is also what keeps
 several of them below the transcript's AA floor as shipped: the body text,
 the timestamps, the blue link and the red and orange markers are all a step
 stronger here, in the same hues. */
nonisolated extension TranscriptThemePalette {
	static let solarized = TranscriptThemePalette(
		background: TranscriptTheme.pair(light: 0xFDF6E3, dark: 0x002B36, contrastLight: 0xFDF6E3, contrastDark: 0x000000),
		primaryText: TranscriptTheme.pair(light: 0x576D75, dark: 0x88A0A9, contrastLight: 0x000000, contrastDark: 0xFFFFFF),
		secondaryText: TranscriptTheme.pair(light: 0x586E75, dark: 0x93A1A1, contrastLight: 0x3A3A3C, contrastDark: 0xE5E5EA),
		timestampText: TranscriptTheme.pair(light: 0x5D717A, dark: 0x86A0AA, contrastLight: 0x3A3A3C, contrastDark: 0xE5E5EA),
		eventText: TranscriptTheme.pair(light: 0x5C6E77, dark: 0x849EA8, contrastLight: 0x2C2C2E, contrastDark: 0xEBEBF0),
		link: TranscriptTheme.pair(light: 0x1E6FB5, dark: 0x3A9BDC, contrastLight: 0x0040A0, contrastDark: 0x9CC8FF),
		localNickname: TranscriptTheme.pair(light: 0x4F6F00, dark: 0x859900, contrastLight: 0x00522D, contrastDark: 0x8CEFB8),
		remoteNickname: TranscriptTheme.pair(light: 0xC42B6B, dark: 0xE45DA6, contrastLight: 0x3B2A80, contrastDark: 0xD3C6FF),
		highlightBackground: TranscriptTheme.pair(light: 0xEEE8D5, dark: 0x073642, contrastLight: 0xFFE066, contrastDark: 0x634A00),
		highlightText: TranscriptTheme.pair(light: 0x4C6067, dark: 0x93A1A1, contrastLight: 0x000000, contrastDark: 0xFFFFFF),
		bubbleIncoming: TranscriptTheme.pair(light: 0xF4EBD2, dark: 0x062A35, contrastLight: 0xDCDCDE, contrastDark: 0x48484A),
		bubbleOutgoing: TranscriptTheme.pair(light: 0xE6F1F8, dark: 0x051E27, contrastLight: 0xC3E1FF, contrastDark: 0x1A5080),
		unreadMarker: TranscriptTheme.pair(light: 0xC62E2B, dark: 0xEE6A6E, contrastLight: 0xA30010, contrastDark: 0xFF8A80),
		failure: TranscriptTheme.pair(light: 0xB03A0E, dark: 0xE4741C, contrastLight: 0x8B0016, contrastDark: 0xFF9E96),
		chromeBackground: TranscriptTheme.pair(light: 0xEEE8D5, dark: 0x073642, contrastLight: 0xEEE8D5, contrastDark: 0x000000)
	)
}
