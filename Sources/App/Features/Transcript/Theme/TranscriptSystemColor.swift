// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
import Foundation

/** A system colour a theme role can follow instead of its stored pair.

 The raw values are what a theme document stores, so they are a file format
 and never change. Each case names a semantic AppKit colour, or one derived
 from them, so a role that follows it tracks light and dark, Increase
 Contrast and the reader's accent colour the way Messages and Notes do. */
nonisolated enum TranscriptSystemColor: String, Codable, CaseIterable, Sendable {
	/// `NSColor.textBackgroundColor`.
	case textBackground
	/// `NSColor.labelColor`.
	case label
	/// `NSColor.secondaryLabelColor`.
	case secondaryLabel
	/// `NSColor.linkColor`.
	case link
	/// The reader's accent colour washed into the text background: a ground
	/// that carries the accent while label text stays legible on it.
	case accentTint
	/// `NSColor.findHighlightColor`.
	case findHighlight
	/// Black or white, whichever reads on the find highlight.
	case textOnFindHighlight
	/// `NSColor.systemRed`.
	case red

	/** The accent washed into `background`.

	 The fraction is enough to read as the accent and little enough that label
	 text keeps AA contrast on it whatever accent the reader picked, yellow on
	 the dark ground included; the theme contrast tests measure every system
	 accent against this. */
	static func accentTint(accent: NSColor, background: NSColor, isDark: Bool) -> NSColor {
		let fraction: CGFloat = isDark ? 0.2 : 0.15
		let ground = background.usingColorSpace(.sRGB) ?? background
		return (accent.usingColorSpace(.sRGB) ?? accent).blended(withFraction: 1 - fraction, of: ground) ?? ground
	}
}

/** The system colours resolved for one appearance, as plain sRGB values.

 AppKit resolves its semantic colours against a drawing appearance, which
 only the main actor may set up. Rendering reads this value instead, from the
 theme snapshot, so a line drawn anywhere agrees with one drawn on the main
 actor, and the snapshot changes — and the transcript redraws — exactly when
 one of these colours does. */
nonisolated struct TranscriptSystemColors: Equatable, Sendable {
	private var values: [TranscriptSystemColor: TranscriptThemeColor]

	init(_ values: [TranscriptSystemColor: TranscriptThemeColor] = [:]) {
		self.values = values
	}

	subscript(_ color: TranscriptSystemColor) -> TranscriptThemeColor? {
		values[color]
	}

	/// No resolved colours: every system role draws its stored pair.
	static let unresolved = TranscriptSystemColors()
}

@MainActor
extension TranscriptSystemColors {
	/** Resolves every system colour against `appearance`.

	 With increased contrast asked for, a translucent colour is drawn at full
	 opacity: the label colours are the translucent ones, and opaque is the
	 strongest the system draws them. A colour the system already resolves to
	 its high-contrast variant is unchanged by this. */
	static func resolve(in appearance: NSAppearance, increasesContrast: Bool) -> Self {
		let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
		var values: [TranscriptSystemColor: TranscriptThemeColor] = [:]
		appearance.performAsCurrentDrawingAppearance {
			for color in TranscriptSystemColor.allCases {
				guard var resolved = TranscriptThemeColor(color.nsColor(isDark: isDark)) else { continue }
				if increasesContrast {
					resolved.alpha = 1
				}
				values[color] = resolved
			}
		}
		return Self(values)
	}

	/// The colours for the plain light or dark appearance, without increased
	/// contrast: what the theme editor shows in its light and dark columns.
	static func standard(isDark: Bool) -> Self {
		guard let appearance = NSAppearance(named: isDark ? .darkAqua : .aqua) else { return .unresolved }
		return resolve(in: appearance, increasesContrast: false)
	}

	/// The colours for the application's appearance right now.
	static func current(isDark: Bool, increasesContrast: Bool) -> Self {
		resolve(in: appearance(isDark: isDark), increasesContrast: increasesContrast)
	}

	/** The appearance to resolve against.

	 The application's own appearance carries the system's high-contrast
	 variants while Increase Contrast is on, so it is used whenever it agrees
	 with the light or dark choice. When the app overrides the system's choice,
	 the plain named appearance stands in. */
	private static func appearance(isDark: Bool) -> NSAppearance {
		let application = NSApp?.effectiveAppearance
		let named: NSAppearance.Name = isDark ? .darkAqua : .aqua
		if let application, application.bestMatch(from: [.aqua, .darkAqua]) == named {
			return application
		}
		return NSAppearance(named: named) ?? NSAppearance.currentDrawing()
	}
}

private extension TranscriptSystemColor {
	/// The AppKit colour, read inside a drawing appearance.
	func nsColor(isDark: Bool) -> NSColor {
		switch self {
		case .textBackground:
			.textBackgroundColor
		case .label:
			.labelColor
		case .secondaryLabel:
			.secondaryLabelColor
		case .link:
			.linkColor
		case .accentTint:
			Self.accentTint(accent: .controlAccentColor, background: .textBackgroundColor, isDark: isDark)
		case .findHighlight:
			.findHighlightColor
		case .textOnFindHighlight:
			NSColor.findHighlightColor.legibleForeground
		case .red:
			.systemRed
		}
	}
}
