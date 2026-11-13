// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/** The Nord palette: Polar Night grounds with Snow Storm text, and the
 Snow Storm ground with Polar Night text for the light side.

 Nord's comment gray and its red read below the transcript's AA floor as
 shipped, so those roles are a step stronger here. The frost and aurora
 accents are otherwise Nord's own. */
nonisolated extension TranscriptThemePalette {
	static let nord = TranscriptThemePalette(
		background: TranscriptTheme.pair(light: 0xECEFF4, dark: 0x2E3440, contrastLight: 0xECEFF4, contrastDark: 0x000000),
		primaryText: TranscriptTheme.pair(light: 0x2E3440, dark: 0xECEFF4, contrastLight: 0x000000, contrastDark: 0xFFFFFF),
		secondaryText: TranscriptTheme.pair(light: 0x4C566A, dark: 0xACB4C4, contrastLight: 0x3A3A3C, contrastDark: 0xEBEBEF),
		timestampText: TranscriptTheme.pair(light: 0x565D6B, dark: 0xABB2C3, contrastLight: 0x3A3A3C, contrastDark: 0xEBEBEF),
		eventText: TranscriptTheme.pair(light: 0x555D74, dark: 0xAAB2C3, contrastLight: 0x2C2C2E, contrastDark: 0xEBEBF0),
		link: TranscriptTheme.pair(light: 0x2A6380, dark: 0x88C0D0, contrastLight: 0x003E9C, contrastDark: 0xDFEDFF),
		localNickname: TranscriptTheme.pair(light: 0x41662A, dark: 0xA3BE8C, contrastLight: 0x004E2B, contrastDark: 0xC4F7DA),
		remoteNickname: TranscriptTheme.pair(light: 0x794F73, dark: 0xC5A9C1, contrastLight: 0x3B2A80, contrastDark: 0xEEE9FF),
		highlightBackground: TranscriptTheme.pair(light: 0xD8DEE9, dark: 0x4C566A, contrastLight: 0xFFE066, contrastDark: 0x634A00),
		highlightText: TranscriptTheme.pair(light: 0x2E3440, dark: 0xECEFF4, contrastLight: 0x000000, contrastDark: 0xFFFFFF),
		bubbleIncoming: TranscriptTheme.pair(light: 0xD8DEE9, dark: 0x3B4252, contrastLight: 0xDCDCDE, contrastDark: 0x48484A),
		bubbleOutgoing: TranscriptTheme.pair(light: 0xC9D9E8, dark: 0x334659, contrastLight: 0xC3E1FF, contrastDark: 0x1A5080),
		unreadMarker: TranscriptTheme.pair(light: 0xA93A46, dark: 0xD68A95, contrastLight: 0xA30010, contrastDark: 0xFF8A80),
		failure: TranscriptTheme.pair(light: 0x9A3412, dark: 0xDDA593, contrastLight: 0x8B0016, contrastDark: 0xFFE6E4),
		chromeBackground: TranscriptTheme.pair(light: 0xD8DEE9, dark: 0x242933, contrastLight: 0xD8DEE9, contrastDark: 0x000000)
	)
}
