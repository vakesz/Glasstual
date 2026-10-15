// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing

/// The shipped preset themes: one stored document each, held to the same
/// validity and contrast floors as a hand-built theme.
@Suite("Transcript theme presets")
struct TranscriptThemePresetTests {
	@Test("Every preset names a distinct title")
	func presetTitlesAreDistinct() {
		let titles = TranscriptThemePreset.allCases.map(\.title)
		#expect(Set(titles).count == titles.count)
		#expect(titles.allSatisfy { $0.isEmpty == false })
	}

	@Test("Every preset theme is a valid stored document")
	func presetsAreValid() {
		for preset in TranscriptThemePreset.allCases {
			let theme = preset.theme()
			#expect(theme.isValid, "\(preset.title)")
			#expect(theme.formatVersion == TranscriptTheme.currentFormatVersion, "\(preset.title)")
		}
	}

	@Test("Every preset round-trips through the stored document format")
	func presetsRoundTrip() throws {
		let encoder = PropertyListEncoder()
		encoder.outputFormat = .xml
		for preset in TranscriptThemePreset.allCases {
			let data = try encoder.encode(preset.theme())
			#expect(try TranscriptTheme.decoded(from: data) == preset.theme())
		}
	}

	@Test("Only shipped themes read as uncustomized")
	func shippedThemesAreNotCustom() {
		for theme in TranscriptThemePreset.allShippedThemes {
			#expect(TranscriptThemePreset.allShippedThemes.contains(theme))
		}
		var customized = TranscriptThemePreset.allCases[0].theme()
		customized.fontSize += 1
		#expect(TranscriptThemePreset.allShippedThemes.contains(customized) == false)
	}
}

/// Every preset palette against the grounds it draws on, held to the same
/// floors as the default palette: AA in normal mode, AAA once increased
/// contrast is asked for.
@Suite("Preset palette contrast")
struct TranscriptThemePresetContrastTests {
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

	private var palettes: [(String, TranscriptThemePalette)] {
		TranscriptThemePreset.allCases.map { ($0.title, $0.theme().palette) }
	}

	@Test("Every preset text role clears AA contrast in both appearances")
	func presetTextRolesClearAAContrast() {
		for (title, palette) in palettes {
			for isDark in [false, true] {
				let ground = palette.background.resolved(isDark: isDark)
				for role in textRoles {
					let ratio = palette[keyPath: role.color].resolved(isDark: isDark)
						.contrastRatio(against: ground)
					#expect(ratio >= 4.5, "\(title) \(role.name) \(isDark ? "dark" : "light"): \(ratio)")
				}
				let highlight = palette.highlightText.resolved(isDark: isDark)
					.contrastRatio(against: palette.highlightBackground.resolved(isDark: isDark))
				#expect(highlight >= 4.5, "\(title) highlightText \(isDark ? "dark" : "light"): \(highlight)")
				for bubble in [palette.bubbleIncoming, palette.bubbleOutgoing] {
					let ratio = palette.primaryText.resolved(isDark: isDark)
						.contrastRatio(against: bubble.resolved(isDark: isDark))
					#expect(ratio >= 4.5, "\(title) primaryText on bubble \(isDark ? "dark" : "light"): \(ratio)")
				}
			}
		}
	}

	@Test("Every preset role clears AAA contrast once increased contrast is asked for")
	func presetHighContrastRolesClearAAAContrast() {
		for (title, palette) in palettes {
			for isDark in [false, true] {
				let ground = palette.background.resolved(isDark: isDark, increasesContrast: true)
				for role in textRoles {
					let ratio = palette[keyPath: role.color]
						.resolved(isDark: isDark, increasesContrast: true)
						.contrastRatio(against: ground)
					#expect(ratio >= 7, "\(title) \(role.name) \(isDark ? "dark" : "light"): \(ratio)")
				}
				let highlight = palette.highlightText.resolved(isDark: isDark, increasesContrast: true)
					.contrastRatio(against: palette.highlightBackground.resolved(isDark: isDark, increasesContrast: true))
				#expect(highlight >= 7, "\(title) highlightText \(isDark ? "dark" : "light"): \(highlight)")
				for bubble in [palette.bubbleIncoming, palette.bubbleOutgoing] {
					let ratio = palette.primaryText.resolved(isDark: isDark, increasesContrast: true)
						.contrastRatio(against: bubble.resolved(isDark: isDark, increasesContrast: true))
					#expect(ratio >= 7, "\(title) primaryText on bubble \(isDark ? "dark" : "light"): \(ratio)")
				}
			}
		}
	}
}
