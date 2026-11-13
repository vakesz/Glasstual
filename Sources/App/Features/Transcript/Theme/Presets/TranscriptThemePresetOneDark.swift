// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/** Atom's One Dark paired with One Light.

 Both sides are upstream's own values except where the transcript's AA floor
 asks for more: One's comments and its light green and blue sit below it, so
 those three roles are a step stronger here. */
nonisolated extension TranscriptThemePalette {
	static let oneDark = TranscriptThemePalette(
		background: TranscriptTheme.pair(light: 0xFAFAFA, dark: 0x282C34, contrastLight: 0xFAFAFA, contrastDark: 0x000000),
		primaryText: TranscriptTheme.pair(light: 0x383A42, dark: 0xABB2BF, contrastLight: 0x000000, contrastDark: 0xFFFFFF),
		secondaryText: TranscriptTheme.pair(light: 0x636671, dark: 0xA6ACBA, contrastLight: 0x3A3A3C, contrastDark: 0xEBEBEF),
		timestampText: TranscriptTheme.pair(light: 0x66686F, dark: 0xA6AAB6, contrastLight: 0x3A3A3C, contrastDark: 0xEBEBEF),
		eventText: TranscriptTheme.pair(light: 0x5F626B, dark: 0xA5AABA, contrastLight: 0x2C2C2E, contrastDark: 0xEBEBF0),
		link: TranscriptTheme.pair(light: 0x2E61D4, dark: 0x63B0EF, contrastLight: 0x003E9C, contrastDark: 0xDFEDFF),
		localNickname: TranscriptTheme.pair(light: 0x33763A, dark: 0x98C379, contrastLight: 0x004E2B, contrastDark: 0xC4F7DA),
		remoteNickname: TranscriptTheme.pair(light: 0xA626A4, dark: 0xD294E4, contrastLight: 0x3B2A80, contrastDark: 0xEEE9FF),
		highlightBackground: TranscriptTheme.pair(light: 0xE5E5E6, dark: 0x3E4451, contrastLight: 0xFFE066, contrastDark: 0x634A00),
		highlightText: TranscriptTheme.pair(light: 0x383A42, dark: 0xABB2BF, contrastLight: 0x000000, contrastDark: 0xFFFFFF),
		bubbleIncoming: TranscriptTheme.pair(light: 0xEDEDEF, dark: 0x2C313C, contrastLight: 0xDCDCDE, contrastDark: 0x48484A),
		bubbleOutgoing: TranscriptTheme.pair(light: 0xDCEAFC, dark: 0x28405C, contrastLight: 0xC3E1FF, contrastDark: 0x1A5080),
		unreadMarker: TranscriptTheme.pair(light: 0xC93A3A, dark: 0xE57E85, contrastLight: 0xA30010, contrastDark: 0xFF8A80),
		failure: TranscriptTheme.pair(light: 0xCA1243, dark: 0xEA9398, contrastLight: 0x8B0016, contrastDark: 0xFFE6E4),
		chromeBackground: TranscriptTheme.pair(light: 0xECECEE, dark: 0x21252B, contrastLight: 0xECECEE, contrastDark: 0x000000)
	)
}
