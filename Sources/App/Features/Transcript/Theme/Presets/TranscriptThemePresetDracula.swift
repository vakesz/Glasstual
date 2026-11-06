// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/** The Dracula palette with a light companion in its spirit.

 Dracula ships dark only, so the light side carries the same accents against
 a paper ground, darkened where the transcript's AA floor asks for it. The
 dark side is Dracula's own values except for the comment gray and the red,
 which sit below the floor as shipped. */
nonisolated extension TranscriptThemePalette {
	static let dracula = TranscriptThemePalette(
		background: TranscriptTheme.pair(light: 0xF8F8F2, dark: 0x282A36, contrastLight: 0xF8F8F2, contrastDark: 0x000000),
		primaryText: TranscriptTheme.pair(light: 0x282A36, dark: 0xF8F8F2, contrastLight: 0x000000, contrastDark: 0xFFFFFF),
		secondaryText: TranscriptTheme.pair(light: 0x565A7A, dark: 0xB6B8D0, contrastLight: 0x3A3A3C, contrastDark: 0xEBEBEF),
		timestampText: TranscriptTheme.pair(light: 0x616388, dark: 0x9CA3D1, contrastLight: 0x3A3A3C, contrastDark: 0xEBEBEF),
		eventText: TranscriptTheme.pair(light: 0x4C5070, dark: 0xA2A4C8, contrastLight: 0x2C2C2E, contrastDark: 0xEBEBF0),
		link: TranscriptTheme.pair(light: 0x067180, dark: 0x8BE9FD, contrastLight: 0x003E9C, contrastDark: 0xDFEDFF),
		localNickname: TranscriptTheme.pair(light: 0x1C7631, dark: 0x50FA7B, contrastLight: 0x004E2B, contrastDark: 0xC4F7DA),
		remoteNickname: TranscriptTheme.pair(light: 0x7E3BD1, dark: 0xBD93F9, contrastLight: 0x3B2A80, contrastDark: 0xEEE9FF),
		highlightBackground: TranscriptTheme.pair(light: 0xF1FA8C, dark: 0x44475A, contrastLight: 0xFFE066, contrastDark: 0x634A00),
		highlightText: TranscriptTheme.pair(light: 0x282A36, dark: 0xF8F8F2, contrastLight: 0x000000, contrastDark: 0xFFFFFF),
		bubbleIncoming: TranscriptTheme.pair(light: 0xE8E6D9, dark: 0x343642, contrastLight: 0xDCDCDE, contrastDark: 0x48484A),
		bubbleOutgoing: TranscriptTheme.pair(light: 0xD6E9F8, dark: 0x2E3A55, contrastLight: 0xC3E1FF, contrastDark: 0x1A5080),
		unreadMarker: TranscriptTheme.pair(light: 0xC92A2A, dark: 0xFF5555, contrastLight: 0xA30010, contrastDark: 0xFF8A80),
		failure: TranscriptTheme.pair(light: 0xB31D28, dark: 0xEF80B4, contrastLight: 0x8B0016, contrastDark: 0xFFE6E4),
		chromeBackground: TranscriptTheme.pair(light: 0xEDEAE0, dark: 0x21222C, contrastLight: 0xEDEAE0, contrastDark: 0x000000)
	)
}
