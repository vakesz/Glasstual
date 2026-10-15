// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

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

	/** The increased-contrast pair is what the system's Increase Contrast
	 setting asks for, so it is held to the AAA minimum rather than the AA one
	 the ordinary pair clears — otherwise turning the setting on would promise
	 something it does not give. */
	@Test("Every role clears AAA contrast once increased contrast is asked for")
	func highContrastRolesClearAAAContrast() {
		let palette = TranscriptTheme.defaultPalette

		for isDark in [false, true] {
			let ground = palette.background.resolved(isDark: isDark, increasesContrast: true)

			for role in textRoles {
				let ratio = palette[keyPath: role.color]
					.resolved(isDark: isDark, increasesContrast: true)
					.contrastRatio(against: ground)
				#expect(ratio >= 7, "\(role.name) on the \(isDark ? "dark" : "light") ground: \(ratio)")
			}

			let highlight = palette.highlightText.resolved(isDark: isDark, increasesContrast: true)
				.contrastRatio(against: palette.highlightBackground.resolved(isDark: isDark, increasesContrast: true))
			#expect(highlight >= 7, "highlightText on the \(isDark ? "dark" : "light") highlight: \(highlight)")

			for bubble in [palette.bubbleIncoming, palette.bubbleOutgoing] {
				let ratio = palette.primaryText.resolved(isDark: isDark, increasesContrast: true)
					.contrastRatio(against: bubble.resolved(isDark: isDark, increasesContrast: true))
				#expect(ratio >= 7, "primaryText on a \(isDark ? "dark" : "light") bubble: \(ratio)")
			}
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

/** The system's label colours on every shipped chrome ground.

 The columns keep the label colours for their rows, so the chrome has to
 carry them: primary labels hold the same AAA floor as the increased-contrast
 transcript, while secondary labels hold the 3:1 floor WCAG asks of large
 text — secondary content is exempt from the body-text minimum by design,
 here and in Apple's own palettes. Both are measured composited, because the
 label colours are translucent and read as what they composite to, not as
 what their components say. */
@MainActor
@Suite("Window chrome contrast")
struct TranscriptThemeChromeContrastTests {
	@Test("System labels clear contrast on every shipped chrome ground", arguments: [false, true])
	func chromeLabelsClearContrast(isDark: Bool) throws {
		let appearance = try #require(NSAppearance(named: isDark ? .darkAqua : .aqua))
		var measured: [ChromeMeasurement] = []
		appearance.performAsCurrentDrawingAppearance {
			for (title, palette) in Self.grounds {
				for highContrast in [false, true] {
					let ground = Self.srgb(palette.chromeBackground.resolved(
						isDark: isDark,
						increasesContrast: highContrast
					))
					measured.append(ChromeMeasurement(
						title: title,
						highContrast: highContrast,
						primary: Self.compositedRatio(Self.srgb(.labelColor), over: ground),
						secondary: Self.compositedRatio(Self.srgb(.secondaryLabelColor), over: ground)
					))
				}
			}
		}
		for result in measured {
			let mode = "\(result.title) \(isDark ? "dark" : "light")\(result.highContrast ? " high-contrast" : "")"
			#expect(result.primary >= 7, "\(mode) primary label: \(result.primary)")
			#expect(result.secondary >= 3, "\(mode) secondary label: \(result.secondary)")
		}
	}

	private struct ChromeMeasurement {
		var title: String
		var highContrast: Bool
		var primary: Double
		var secondary: Double
	}

	private static var grounds: [(String, TranscriptThemePalette)] {
		[("Default", TranscriptTheme.defaultPalette)]
			+ TranscriptThemePreset.allCases.map { ($0.title, $0.theme().palette) }
	}

	private static func srgb(_ color: NSColor) -> SRGBColor {
		let resolved = color.usingColorSpace(.sRGB) ?? color
		return SRGBColor(
			red: Double(resolved.redComponent),
			green: Double(resolved.greenComponent),
			blue: Double(resolved.blueComponent),
			alpha: Double(resolved.alphaComponent)
		)
	}

	private struct SRGBColor {
		var red: Double
		var green: Double
		var blue: Double
		var alpha: Double
	}

	/// The WCAG ratio of `foreground` source-over `ground`, in sRGB.
	private static func compositedRatio(_ foreground: SRGBColor, over ground: SRGBColor) -> Double {
		func channel(_ value: Double) -> Double {
			value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
		}
		let mixed = (
			foreground.alpha * foreground.red + (1 - foreground.alpha) * ground.red,
			foreground.alpha * foreground.green + (1 - foreground.alpha) * ground.green,
			foreground.alpha * foreground.blue + (1 - foreground.alpha) * ground.blue
		)
		let first = 0.2126 * channel(mixed.0) + 0.7152 * channel(mixed.1) + 0.0722 * channel(mixed.2)
		let second = 0.2126 * channel(ground.red) + 0.7152 * channel(ground.green) + 0.0722 * channel(ground.blue)
		return (max(first, second) + 0.05) / (min(first, second) + 0.05)
	}
}
