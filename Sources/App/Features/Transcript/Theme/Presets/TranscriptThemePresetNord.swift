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
		secondaryText: TranscriptTheme.pair(light: 0x4C566A, dark: 0xA3ADBE, contrastLight: 0x3A3A3C, contrastDark: 0xE5E5EA),
		timestampText: TranscriptTheme.pair(light: 0x646C7C, dark: 0x979FB5, contrastLight: 0x3A3A3C, contrastDark: 0xE5E5EA),
		eventText: TranscriptTheme.pair(light: 0x59627A, dark: 0x939DB3, contrastLight: 0x2C2C2E, contrastDark: 0xEBEBF0),
		link: TranscriptTheme.pair(light: 0x2F6F8F, dark: 0x88C0D0, contrastLight: 0x0040A0, contrastDark: 0x9CC8FF),
		localNickname: TranscriptTheme.pair(light: 0x48722F, dark: 0xA3BE8C, contrastLight: 0x00522D, contrastDark: 0x8CEFB8),
		remoteNickname: TranscriptTheme.pair(light: 0x8A5A83, dark: 0xB998B5, contrastLight: 0x3B2A80, contrastDark: 0xD3C6FF),
		highlightBackground: TranscriptTheme.pair(light: 0xD8DEE9, dark: 0x4C566A, contrastLight: 0xFFE066, contrastDark: 0x634A00),
		highlightText: TranscriptTheme.pair(light: 0x2E3440, dark: 0xECEFF4, contrastLight: 0x000000, contrastDark: 0xFFFFFF),
		bubbleIncoming: TranscriptTheme.pair(light: 0xD8DEE9, dark: 0x3B4252, contrastLight: 0xDCDCDE, contrastDark: 0x48484A),
		bubbleOutgoing: TranscriptTheme.pair(light: 0xC9D9E8, dark: 0x334659, contrastLight: 0xC3E1FF, contrastDark: 0x1A5080),
		unreadMarker: TranscriptTheme.pair(light: 0xA93A46, dark: 0xD68A95, contrastLight: 0xA30010, contrastDark: 0xFF8A80),
		failure: TranscriptTheme.pair(light: 0x9A3412, dark: 0xD6917C, contrastLight: 0x8B0016, contrastDark: 0xFF9E96),
		chromeBackground: TranscriptTheme.pair(light: 0xD8DEE9, dark: 0x242933, contrastLight: 0xD8DEE9, contrastDark: 0x000000)
	)
}
