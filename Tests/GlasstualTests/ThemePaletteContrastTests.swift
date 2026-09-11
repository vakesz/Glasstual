/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import AppKit
@testable import Glasstual
import Testing

/** The shipped palette against the ground it is drawn on.

 The transcript draws every one of these roles as text, some of it a point
 smaller than the body, so each has to clear the 4.5:1 the WCAG AA contrast
 minimum asks of body text. `timestampText` is the role this is really here for:
 it is new — timestamps used to be drawn in `secondaryText` — and it is meant to
 be quieter than the secondary text beside it, which is exactly the choice that
 goes below the minimum if nobody measures it. */
@Suite("Default transcript palette contrast")
struct ThemePaletteContrastTests {
	private typealias Role = (name: String, color: KeyPath<TranscriptThemePalette, AdaptiveTranscriptColor>)

	private let textRoles: [Role] = [
		("primaryText", \.primaryText),
		("secondaryText", \.secondaryText),
		("timestampText", \.timestampText),
		("eventText", \.eventText),
		("link", \.link),
		("localNickname", \.localNickname),
		("remoteNickname", \.remoteNickname),
		("failure", \.failure),
	]

	@Test("Every text role clears AA contrast against the default ground in both appearances")
	func textRolesClearAAContrast() {
		let palette = TranscriptTheme.defaultPalette

		for isDark in [false, true] {
			let ground = palette.background.resolved(isDark: isDark)

			for role in textRoles {
				let ratio = palette[keyPath: role.color].resolved(isDark: isDark).contrastRatio(against: ground)
				#expect(ratio >= 4.5, "\(role.name) on the \(isDark ? "dark" : "light") ground: \(ratio)")
			}
		}
	}

	/// Highlighted text is drawn on the highlight, not on the transcript ground.
	@Test("Highlighted text clears AA contrast against the highlight it sits on")
	func highlightTextClearsAAContrast() {
		let palette = TranscriptTheme.defaultPalette

		for isDark in [false, true] {
			let ratio = palette.highlightText.resolved(isDark: isDark)
				.contrastRatio(against: palette.highlightBackground.resolved(isDark: isDark))
			#expect(ratio >= 4.5, "highlightText on the \(isDark ? "dark" : "light") highlight: \(ratio)")
		}
	}

	/// The clock is meant to recede behind the names and the message it labels;
	/// what it may not do is recede out of legibility.
	@Test("The timestamp is quieter than the secondary text it used to share")
	func timestampIsQuieterThanSecondaryText() {
		let palette = TranscriptTheme.defaultPalette

		for isDark in [false, true] {
			let ground = palette.background.resolved(isDark: isDark)
			let timestamp = palette.timestampText.resolved(isDark: isDark).contrastRatio(against: ground)
			let secondary = palette.secondaryText.resolved(isDark: isDark).contrastRatio(against: ground)
			#expect(timestamp < secondary, "\(isDark ? "dark" : "light"): \(timestamp) against \(secondary)")
		}
	}
}
