// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/** The Tokyo Night palette with a day variant in its spirit.

 The dark side is Tokyo Night's own background, foreground and accents. The
 day side keeps the same hues against a light ground; upstream's day grays
 are quieter than the transcript's AA floor allows, so the secondary roles
 are a step stronger here. */
nonisolated extension TranscriptThemePalette {
	static let tokyoNight = TranscriptThemePalette(
		background: TranscriptTheme.pair(light: 0xE1E2E7, dark: 0x1A1B26, contrastLight: 0xE1E2E7, contrastDark: 0x000000),
		primaryText: TranscriptTheme.pair(light: 0x343B58, dark: 0xC0CAF5, contrastLight: 0x000000, contrastDark: 0xFFFFFF),
		secondaryText: TranscriptTheme.pair(light: 0x4F587F, dark: 0x9AA5CE, contrastLight: 0x3A3A3C, contrastDark: 0xE5E5EA),
		timestampText: TranscriptTheme.pair(light: 0x525E87, dark: 0x7A86B8, contrastLight: 0x3A3A3C, contrastDark: 0xE5E5EA),
		eventText: TranscriptTheme.pair(light: 0x4F587F, dark: 0x8B95C2, contrastLight: 0x2C2C2E, contrastDark: 0xEBEBF0),
		link: TranscriptTheme.pair(light: 0x2959AA, dark: 0x7AA2F7, contrastLight: 0x0040A0, contrastDark: 0x9CC8FF),
		localNickname: TranscriptTheme.pair(light: 0x2F6B3E, dark: 0x9ECE6A, contrastLight: 0x00522D, contrastDark: 0x8CEFB8),
		remoteNickname: TranscriptTheme.pair(light: 0x6A4FB5, dark: 0xBB9AF7, contrastLight: 0x3B2A80, contrastDark: 0xD3C6FF),
		highlightBackground: TranscriptTheme.pair(light: 0xFFE9A8, dark: 0x3B3E5C, contrastLight: 0xFFE066, contrastDark: 0x634A00),
		highlightText: TranscriptTheme.pair(light: 0x343B58, dark: 0xC0CAF5, contrastLight: 0x000000, contrastDark: 0xFFFFFF),
		bubbleIncoming: TranscriptTheme.pair(light: 0xD2D4DE, dark: 0x24283B, contrastLight: 0xDCDCDE, contrastDark: 0x48484A),
		bubbleOutgoing: TranscriptTheme.pair(light: 0xC9D8F5, dark: 0x2C3A5E, contrastLight: 0xC3E1FF, contrastDark: 0x1A5080),
		unreadMarker: TranscriptTheme.pair(light: 0xA82446, dark: 0xF7768E, contrastLight: 0xA30010, contrastDark: 0xFF8A80),
		failure: TranscriptTheme.pair(light: 0x8E2040, dark: 0xFF5D5D, contrastLight: 0x8B0016, contrastDark: 0xFF9E96),
		chromeBackground: TranscriptTheme.pair(light: 0xDDE0E8, dark: 0x16161E, contrastLight: 0xDDE0E8, contrastDark: 0x000000)
	)
}
