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
		secondaryText: TranscriptTheme.pair(light: 0x4F587F, dark: 0x9BA6CE, contrastLight: 0x3A3A3C, contrastDark: 0xEBEBEF),
		timestampText: TranscriptTheme.pair(light: 0x4F5A82, dark: 0x9BA4CA, contrastLight: 0x3A3A3C, contrastDark: 0xEBEBEF),
		eventText: TranscriptTheme.pair(light: 0x4F587F, dark: 0x9BA4CA, contrastLight: 0x2C2C2E, contrastDark: 0xEBEBF0),
		link: TranscriptTheme.pair(light: 0x2959AA, dark: 0x7EA5F7, contrastLight: 0x003E9C, contrastDark: 0xDFEDFF),
		localNickname: TranscriptTheme.pair(light: 0x2D673C, dark: 0x9ECE6A, contrastLight: 0x004E2B, contrastDark: 0xC4F7DA),
		remoteNickname: TranscriptTheme.pair(light: 0x6449AE, dark: 0xBB9AF7, contrastLight: 0x3B2A80, contrastDark: 0xEEE9FF),
		highlightBackground: TranscriptTheme.pair(light: 0xFFE9A8, dark: 0x3B3E5C, contrastLight: 0xFFE066, contrastDark: 0x634A00),
		highlightText: TranscriptTheme.pair(light: 0x343B58, dark: 0xC0CAF5, contrastLight: 0x000000, contrastDark: 0xFFFFFF),
		bubbleIncoming: TranscriptTheme.pair(light: 0xD2D4DE, dark: 0x24283B, contrastLight: 0xDCDCDE, contrastDark: 0x48484A),
		bubbleOutgoing: TranscriptTheme.pair(light: 0xC9D8F5, dark: 0x2C3A5E, contrastLight: 0xC3E1FF, contrastDark: 0x1A5080),
		unreadMarker: TranscriptTheme.pair(light: 0xA82446, dark: 0xF7768E, contrastLight: 0xA30010, contrastDark: 0xFF8A80),
		failure: TranscriptTheme.pair(light: 0x8E2040, dark: 0xFF7E7E, contrastLight: 0x8B0016, contrastDark: 0xFFE6E4),
		chromeBackground: TranscriptTheme.pair(light: 0xDDE0E8, dark: 0x16161E, contrastLight: 0xDDE0E8, contrastDark: 0x000000)
	)
}
