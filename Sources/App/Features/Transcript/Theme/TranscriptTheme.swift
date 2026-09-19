// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
import Foundation

/// A portable sRGB colour. Theme files use components rather than archived
/// `NSColor` objects so they remain readable and stable across macOS releases.
nonisolated struct TranscriptThemeColor: Codable, Equatable, Sendable {
	var red: Double
	var green: Double
	var blue: Double
	var alpha: Double

	init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
		self.red = red
		self.green = green
		self.blue = blue
		self.alpha = alpha
	}

	init?(_ color: NSColor) {
		guard let color = color.usingColorSpace(.sRGB) else {
			return nil
		}
		self.init(
			red: color.redComponent,
			green: color.greenComponent,
			blue: color.blueComponent,
			alpha: color.alphaComponent
		)
	}

	var color: NSColor {
		NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
	}

	var isValid: Bool {
		[red, green, blue, alpha].allSatisfy { $0.isFinite && (0 ... 1).contains($0) }
	}
}

/** Light and dark variants for one semantic role in a transcript, and the
 stronger pair the role draws as while the reader has asked the system for
 increased contrast.

 The stronger pair is optional because it is a statement about a colour
 somebody chose: the shipped palette has one for every role, and a colour the
 reader picked themselves speaks for itself in both settings, which is why
 editing `light` or `dark` drops the variant beside it. */
nonisolated struct AdaptiveTranscriptColor: Codable, Equatable, Sendable {
	var light: TranscriptThemeColor {
		didSet { highContrastLight = nil }
	}

	var dark: TranscriptThemeColor {
		didSet { highContrastDark = nil }
	}

	private(set) var highContrastLight: TranscriptThemeColor?
	private(set) var highContrastDark: TranscriptThemeColor?

	init(light: TranscriptThemeColor, dark: TranscriptThemeColor) {
		self.light = light
		self.dark = dark
	}

	init(
		light: TranscriptThemeColor,
		dark: TranscriptThemeColor,
		highContrastLight: TranscriptThemeColor,
		highContrastDark: TranscriptThemeColor
	) {
		self.light = light
		self.dark = dark
		self.highContrastLight = highContrastLight
		self.highContrastDark = highContrastDark
	}

	func resolved(isDark: Bool, increasesContrast: Bool = false) -> NSColor {
		let stronger = increasesContrast ? (isDark ? highContrastDark : highContrastLight) : nil
		return (stronger ?? (isDark ? dark : light)).color
	}

	var isValid: Bool {
		light.isValid && dark.isValid
			&& highContrastLight?.isValid != false && highContrastDark?.isValid != false
	}
}

nonisolated enum TranscriptThemeLayout: String, Codable, CaseIterable, Sendable {
	case lines
	case bubbles
}

/// Every colour the native transcript draws, named by purpose rather than by
/// where a former stylesheet happened to use it.
nonisolated struct TranscriptThemePalette: Codable, Equatable, Sendable {
	var background: AdaptiveTranscriptColor
	var primaryText: AdaptiveTranscriptColor
	var secondaryText: AdaptiveTranscriptColor
	/// The clock beside each line, quieter than the secondary text but still
	/// legible: the default is the quietest grey that keeps 4.5:1 against the
	/// default ground.
	var timestampText: AdaptiveTranscriptColor
	var eventText: AdaptiveTranscriptColor
	var link: AdaptiveTranscriptColor
	var localNickname: AdaptiveTranscriptColor
	var remoteNickname: AdaptiveTranscriptColor
	var highlightBackground: AdaptiveTranscriptColor
	var highlightText: AdaptiveTranscriptColor
	var bubbleIncoming: AdaptiveTranscriptColor
	var bubbleOutgoing: AdaptiveTranscriptColor
	var unreadMarker: AdaptiveTranscriptColor
	var failure: AdaptiveTranscriptColor

	/// Every colour role, so a pass over the palette cannot miss one.
	static var roles: [WritableKeyPath<Self, AdaptiveTranscriptColor>] {
		[
			\.background, \.primaryText, \.secondaryText, \.timestampText, \.eventText, \.link,
			\.localNickname, \.remoteNickname, \.highlightBackground, \.highlightText,
			\.bubbleIncoming, \.bubbleOutgoing, \.unreadMarker, \.failure,
		]
	}

	var isValid: Bool {
		Self.roles.allSatisfy { self[keyPath: $0].isValid }
	}
}

/// The one native transcript theme format. It is both the runtime model and
/// the payload written by Export Theme, avoiding adapters between setting,
/// file, and rendering representations.
nonisolated struct TranscriptTheme: Codable, Equatable, Sendable {
	/** The one format this build reads or writes.

	 A document carrying any other version is refused outright rather than
	 guessed at, so the theme store falls back to the shipped theme and says so
	 instead of drawing a half-understood palette.

	 The number is not restarted at 1 along with the archive's: a pre-2.0 theme
	 document says 1 or 2, and keeping the count ahead of both is what makes the
	 version check refuse them. Its high-contrast fields are optional, so a
	 version-1 document would otherwise pass and draw bracketed nicknames with
	 no increased-contrast pair. */
	static let currentFormatVersion = 3

	var formatVersion = currentFormatVersion
	var name: String
	var layout: TranscriptThemeLayout
	var fontName: String
	var fontSize: Double
	var timestampFormat: String
	var nicknameFormat: String
	var lineSpacing: Double
	var messageSpacing: Double
	var horizontalPadding: Double
	var palette: TranscriptThemePalette

	init(
		name: String,
		layout: TranscriptThemeLayout,
		fontName: String = ".AppleSystemUIFont",
		fontSize: Double = 13,
		timestampFormat: String = "%H:%M:%S",
		/* The colon in ``NicknameFormat/default`` is what separates the nickname
			from the message: the renderer's gap alone reads as
			`12:34  @alice  hello`, three columns with nothing saying which one is
			the speaker. */
		nicknameFormat: String = NicknameFormat.default,
		lineSpacing: Double = 2,
		messageSpacing: Double = 3,
		horizontalPadding: Double = 10,
		palette: TranscriptThemePalette
	) {
		self.name = name
		self.layout = layout
		self.fontName = fontName
		self.fontSize = fontSize
		self.timestampFormat = timestampFormat
		self.nicknameFormat = nicknameFormat
		self.lineSpacing = lineSpacing
		self.messageSpacing = messageSpacing
		self.horizontalPadding = horizontalPadding
		self.palette = palette
	}

	static let lines = TranscriptTheme(
		name: "Lines",
		layout: .lines,
		palette: defaultPalette
	)

	static let bubbles = TranscriptTheme(
		name: "Bubbles",
		layout: .bubbles,
		messageSpacing: 7,
		horizontalPadding: 12,
		palette: defaultPalette
	)

	/** The shipped colours.

	 Every role carries a second pair for the system's Increase Contrast
	 setting. Those are not a darker shade for its own sake: each was picked to
	 clear 7:1 against the ground it is drawn on — the WCAG AAA minimum, one
	 step above the 4.5:1 the ordinary pair holds — and the dark ground itself
	 drops to black so the whole transcript gains from it.
	 `ThemePaletteContrastTests` holds both floors. */
	static let defaultPalette = TranscriptThemePalette(
		background: pair(light: 0xFFFFFF, dark: 0x1E1E1E, contrastLight: 0xFFFFFF, contrastDark: 0x000000),
		primaryText: pair(light: 0x202124, dark: 0xF2F2F2, contrastLight: 0x000000, contrastDark: 0xFFFFFF),
		secondaryText: pair(light: 0x6E6E73, dark: 0xA1A1A6, contrastLight: 0x3A3A3C, contrastDark: 0xE5E5EA),
		/* A role of its own, added with the native transcript: timestamps used
			to be drawn in `secondaryText`, which measures 5.07:1 on white and
			6.48:1 on the dark ground. These are deliberately quieter than that —
			a timestamp is the least of what a line says — and were picked to stay
			above the 4.5:1 the WCAG AA contrast minimum asks of body text, which
			this is a point smaller than: 4.65:1 on white, 5.11:1 on dark. The
			increased-contrast pair gives up that quietness, which is the whole
			point of the setting. */
		timestampText: pair(light: 0x747479, dark: 0x8E8E93, contrastLight: 0x3A3A3C, contrastDark: 0xE5E5EA),
		eventText: pair(light: 0x65656A, dark: 0xAEAEB2, contrastLight: 0x2C2C2E, contrastDark: 0xEBEBF0),
		link: pair(light: 0x0068D9, dark: 0x64A8FF, contrastLight: 0x0040A0, contrastDark: 0x9CC8FF),
		localNickname: pair(light: 0x006B3C, dark: 0x67D99A, contrastLight: 0x00522D, contrastDark: 0x8CEFB8),
		remoteNickname: pair(light: 0x5B42A6, dark: 0xB7A3FF, contrastLight: 0x3B2A80, contrastDark: 0xD3C6FF),
		highlightBackground: pair(
			light: 0xFFF1B8, dark: 0x5C4710, contrastLight: 0xFFE066, contrastDark: 0x634A00
		),
		highlightText: pair(light: 0x202124, dark: 0xFFFFFF, contrastLight: 0x000000, contrastDark: 0xFFFFFF),
		bubbleIncoming: pair(light: 0xE9E9EB, dark: 0x363638, contrastLight: 0xDCDCDE, contrastDark: 0x48484A),
		bubbleOutgoing: pair(light: 0xD8ECFF, dark: 0x164A73, contrastLight: 0xC3E1FF, contrastDark: 0x1A5080),
		unreadMarker: pair(light: 0xD70015, dark: 0xFF6961, contrastLight: 0xA30010, contrastDark: 0xFF8A80),
		failure: pair(light: 0xB00020, dark: 0xFF8A80, contrastLight: 0x8B0016, contrastDark: 0xFF9E96)
	)

	private static func pair(
		light: UInt32,
		dark: UInt32,
		contrastLight: UInt32,
		contrastDark: UInt32
	) -> AdaptiveTranscriptColor {
		AdaptiveTranscriptColor(
			light: color(light),
			dark: color(dark),
			highContrastLight: color(contrastLight),
			highContrastDark: color(contrastDark)
		)
	}

	private static func color(_ value: UInt32) -> TranscriptThemeColor {
		TranscriptThemeColor(
			red: Double((value >> 16) & 0xFF) / 255,
			green: Double((value >> 8) & 0xFF) / 255,
			blue: Double(value & 0xFF) / 255
		)
	}

	/** The one way a stored or imported property list becomes a theme: decode,
	 refuse a version this build does not write, and refuse anything the renderer
	 could not draw. */
	static func decoded(from data: Data) throws -> Self {
		let decoded: Self
		do {
			decoded = try PropertyListDecoder().decode(Self.self, from: data)
		} catch {
			throw TranscriptThemeCodingError.invalidDocument
		}

		guard decoded.formatVersion == currentFormatVersion else {
			throw TranscriptThemeCodingError.unsupportedVersion(decoded.formatVersion)
		}

		guard decoded.isValid else {
			throw TranscriptThemeCodingError.invalidDocument
		}

		return decoded
	}

	/// The sizes the transcript renders at. The font picker offers exactly this
	/// range: anything else is rejected by `isValid`, so offering more would
	/// only produce a choice that cannot be applied.
	static let fontSizeRange: ClosedRange<CGFloat> = 9 ... 36

	/** The longest name, font name or format a theme may carry, in characters.

	 Each is drawn or formatted for every transcript line, and an imported
	 document is whatever someone wrote, so none is left unbounded. */
	static let maximumTextLength = 256

	var isValid: Bool {
		formatVersion == Self.currentFormatVersion &&
			name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false &&
			[name, fontName, timestampFormat, nicknameFormat].allSatisfy { $0.count <= Self.maximumTextLength } &&
			fontSize.isFinite && Self.fontSizeRange.contains(fontSize) &&
			lineSpacing.isFinite && (0 ... 16).contains(lineSpacing) &&
			messageSpacing.isFinite && (0 ... 32).contains(messageSpacing) &&
			horizontalPadding.isFinite && (0 ... 48).contains(horizontalPadding) &&
			palette.isValid
	}
}

/// Why a stored or imported theme document was refused, in the words the theme
/// sheet shows.
nonisolated enum TranscriptThemeCodingError: LocalizedError, Equatable, Sendable {
	case invalidDocument
	case unsupportedVersion(Int)

	var errorDescription: String? {
		switch self {
		case .invalidDocument:
			String(localized: .TranscriptTheme.invalidDocument)
		case let .unsupportedVersion(version):
			String(localized: .TranscriptTheme.unsupportedVersion(version))
		}
	}
}
