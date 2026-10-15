// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/** The shipped transcript themes beyond Lines and Bubbles.

 A preset is a value, not a format: applying one writes an ordinary versioned
 ``TranscriptTheme`` document, so import, export, validation and the
 increased-contrast pairs work exactly as they do for a hand-built theme. The
 increased-contrast columns below mirror the default palette's strategy —
 plain grounds with black text in light mode, black grounds with white text
 in dark mode — which is what holds the AAA floors the contrast tests check.
 */
nonisolated enum TranscriptThemePreset: String, CaseIterable, Identifiable, Sendable {
	case github
	case tokyoNight
	case oneDark
	case dracula
	case nord
	case solarized

	var id: String {
		rawValue
	}

	/** The name shown in the preset menu and stored on the applied theme.

	 Proper nouns by design — GitHub, Tokyo Night, Dracula and the rest travel
	 the way product names do — so they are stored verbatim and never
	 localized. */
	var title: String {
		switch self {
		case .github: "GitHub"
		case .tokyoNight: "Tokyo Night"
		case .oneDark: "One Dark"
		case .dracula: "Dracula"
		case .nord: "Nord"
		case .solarized: "Solarized"
		}
	}

	/// The theme choosing this preset writes: the preset's palette under its
	/// title, in the Lines layout. Spacing and fonts stay the reader's own.
	func theme() -> TranscriptTheme {
		TranscriptTheme(name: title, layout: .lines, palette: palette)
	}

	/// Every shipped theme value: Lines, Bubbles and each preset. A stored
	/// theme matching none of these is a customization.
	static var allShippedThemes: [TranscriptTheme] {
		[.lines, .bubbles] + allCases.map { $0.theme() }
	}

	private var palette: TranscriptThemePalette {
		switch self {
		case .github: .github
		case .tokyoNight: .tokyoNight
		case .oneDark: .oneDark
		case .dracula: .dracula
		case .nord: .nord
		case .solarized: .solarized
		}
	}
}
