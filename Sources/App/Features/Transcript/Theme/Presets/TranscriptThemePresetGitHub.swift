// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/** The GitHub Primer palette, light and dark.

 Primer's mid-tone grays and greens sit below the transcript's AA floor as
 shipped, so the timestamp and the green nickname are a step darker and
 brighter respectively than Primer names them. Everything else is Primer's
 own values. */
nonisolated extension TranscriptThemePalette {
	static let github = TranscriptThemePalette(
		background: TranscriptTheme.pair(light: 0xFFFFFF, dark: 0x0D1117, contrastLight: 0xFFFFFF, contrastDark: 0x000000),
		primaryText: TranscriptTheme.pair(light: 0x1F2328, dark: 0xE6EDF3, contrastLight: 0x000000, contrastDark: 0xFFFFFF),
		secondaryText: TranscriptTheme.pair(light: 0x59636E, dark: 0x9198A1, contrastLight: 0x3A3A3C, contrastDark: 0xE5E5EA),
		timestampText: TranscriptTheme.pair(light: 0x5F6D78, dark: 0x7D8590, contrastLight: 0x3A3A3C, contrastDark: 0xE5E5EA),
		eventText: TranscriptTheme.pair(light: 0x5C6672, dark: 0x8B949E, contrastLight: 0x2C2C2E, contrastDark: 0xEBEBF0),
		link: TranscriptTheme.pair(light: 0x0969DA, dark: 0x4493F8, contrastLight: 0x0040A0, contrastDark: 0x9CC8FF),
		localNickname: TranscriptTheme.pair(light: 0x1A7F37, dark: 0x3FB950, contrastLight: 0x00522D, contrastDark: 0x8CEFB8),
		remoteNickname: TranscriptTheme.pair(light: 0x8250DF, dark: 0xBC8CFF, contrastLight: 0x3B2A80, contrastDark: 0xD3C6FF),
		highlightBackground: TranscriptTheme.pair(light: 0xFFF8C5, dark: 0x4D3A00, contrastLight: 0xFFE066, contrastDark: 0x634A00),
		highlightText: TranscriptTheme.pair(light: 0x1F2328, dark: 0xE6EDF3, contrastLight: 0x000000, contrastDark: 0xFFFFFF),
		bubbleIncoming: TranscriptTheme.pair(light: 0xEAECEF, dark: 0x21262D, contrastLight: 0xDCDCDE, contrastDark: 0x48484A),
		bubbleOutgoing: TranscriptTheme.pair(light: 0xDDF4FF, dark: 0x0C2D6B, contrastLight: 0xC3E1FF, contrastDark: 0x1A5080),
		unreadMarker: TranscriptTheme.pair(light: 0xCF222E, dark: 0xF85149, contrastLight: 0xA30010, contrastDark: 0xFF8A80),
		failure: TranscriptTheme.pair(light: 0xA40E26, dark: 0xFF7B72, contrastLight: 0x8B0016, contrastDark: 0xFF9E96),
		chromeBackground: TranscriptTheme.pair(light: 0xF6F8FA, dark: 0x010409, contrastLight: 0xF6F8FA, contrastDark: 0x000000)
	)
}
