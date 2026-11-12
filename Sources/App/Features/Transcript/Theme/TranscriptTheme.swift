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
 editing `light` or `dark` drops the variant beside it.

 A role may instead follow a system colour. The stored pairs then stand in
 wherever no resolved system colour is at hand, such as a printed copy, and
 choosing a colour of one's own stops the role following the system. */
nonisolated struct AdaptiveTranscriptColor: Codable, Equatable, Sendable {
	var light: TranscriptThemeColor {
		didSet {
			highContrastLight = nil
			system = nil
		}
	}

	var dark: TranscriptThemeColor {
		didSet {
			highContrastDark = nil
			system = nil
		}
	}

	private(set) var highContrastLight: TranscriptThemeColor?
	private(set) var highContrastDark: TranscriptThemeColor?
	/// The system colour this role follows, if any.
	private(set) var system: TranscriptSystemColor?

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

	/// The role following `system`, with `fallback` as its stored pairs.
	init(system: TranscriptSystemColor, fallback: AdaptiveTranscriptColor) {
		self = fallback
		self.system = system
	}

	/// The colour drawn for an appearance. A role that follows a system colour
	/// draws it whenever `systemColors` has it resolved.
	func resolved(
		isDark: Bool,
		increasesContrast: Bool = false,
		systemColors: TranscriptSystemColors = .unresolved
	) -> NSColor {
		if let system, let resolved = systemColors[system] {
			return resolved.color
		}
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

/// Every colour the native transcript and its window chrome draw, named by
/// purpose rather than by where a former stylesheet happened to use it.
///
/// The transcript reads every role but the last; the sidebar and the member
/// list draw their grounds from `chromeBackground` and keep the system's
/// own label colours for what sits on them.
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
	/// The ground behind the sidebar and the member list. Opaque by design:
	/// the columns never show the desktop through a material, so a preset
	/// carries the whole window with it.
	var chromeBackground: AdaptiveTranscriptColor

	/// Every colour role, so a pass over the palette cannot miss one.
	static var roles: [WritableKeyPath<Self, AdaptiveTranscriptColor>] {
		[
			\.background, \.primaryText, \.secondaryText, \.timestampText, \.eventText, \.link,
			\.localNickname, \.remoteNickname, \.highlightBackground, \.highlightText,
			\.bubbleIncoming, \.bubbleOutgoing, \.unreadMarker, \.failure, \.chromeBackground,
		]
	}

	var isValid: Bool {
		Self.roles.allSatisfy { self[keyPath: $0].isValid }
	}
}

nonisolated extension CodingUserInfoKey {
	/// Set while decoding a version-3 theme, whose palette predates the
	/// window-chrome ground.
	static let transcriptThemeChromeFallsBackToBackground = CodingUserInfoKey(
		rawValue: "transcriptThemeChromeFallsBackToBackground"
	)!
}

nonisolated extension TranscriptThemePalette {
	/// A version-3 palette has no window-chrome ground. The columns stood on
	/// the transcript ground before they had a colour of their own, so an
	/// upgraded theme keeps standing on it. Any other palette must carry one.
	init(from decoder: Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)
		background = try container.decode(AdaptiveTranscriptColor.self, forKey: .background)
		primaryText = try container.decode(AdaptiveTranscriptColor.self, forKey: .primaryText)
		secondaryText = try container.decode(AdaptiveTranscriptColor.self, forKey: .secondaryText)
		timestampText = try container.decode(AdaptiveTranscriptColor.self, forKey: .timestampText)
		eventText = try container.decode(AdaptiveTranscriptColor.self, forKey: .eventText)
		link = try container.decode(AdaptiveTranscriptColor.self, forKey: .link)
		localNickname = try container.decode(AdaptiveTranscriptColor.self, forKey: .localNickname)
		remoteNickname = try container.decode(AdaptiveTranscriptColor.self, forKey: .remoteNickname)
		highlightBackground = try container.decode(AdaptiveTranscriptColor.self, forKey: .highlightBackground)
		highlightText = try container.decode(AdaptiveTranscriptColor.self, forKey: .highlightText)
		bubbleIncoming = try container.decode(AdaptiveTranscriptColor.self, forKey: .bubbleIncoming)
		bubbleOutgoing = try container.decode(AdaptiveTranscriptColor.self, forKey: .bubbleOutgoing)
		unreadMarker = try container.decode(AdaptiveTranscriptColor.self, forKey: .unreadMarker)
		failure = try container.decode(AdaptiveTranscriptColor.self, forKey: .failure)
		if decoder.userInfo[.transcriptThemeChromeFallsBackToBackground] as? Bool == true {
			chromeBackground = try container.decodeIfPresent(AdaptiveTranscriptColor.self, forKey: .chromeBackground)
				?? background
		} else {
			chromeBackground = try container.decode(AdaptiveTranscriptColor.self, forKey: .chromeBackground)
		}
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
	 no increased-contrast pair.

	 Version 4 adds the window-chrome ground. `decoded(from:)` upgrades a
	 version-3 document with the chrome copied from its transcript ground,
	 which is what the columns stood on before they had a colour of their own.

	 Version 5 lets a role follow a system colour, and the shipped default
	 does. `decoded(from:)` upgrades an older document whose palette is still
	 the one the default used to ship — the reader never chose a colour — to
	 the system palette; any other palette is kept as it was. */
	static let currentFormatVersion = 5

	/// The versions `decoded(from:)` upgrades rather than refuses.
	static let upgradableFormatVersions: ClosedRange<Int> = 3 ... 4

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

	/** The shipped default: the transcript in the system's own colours.

	 The ground, text, links, the outgoing bubble, the highlight and the unread
	 marker follow AppKit's semantic colours, so the transcript tracks light
	 and dark, Increase Contrast and the reader's accent colour as Messages and
	 Notes do. The nickname, incoming bubble and failure roles keep the Classic
	 colours, which were chosen for the same white and #1E1E1E grounds the
	 system text background resolves to. The Classic colours are also every
	 role's stored pair, drawn wherever no system colour is resolved, such as
	 a printed copy. `ThemePaletteContrastTests` measures the result. */
	static let defaultPalette: TranscriptThemePalette = {
		let classic = TranscriptThemePalette.classic
		var palette = classic
		let followed: [(WritableKeyPath<TranscriptThemePalette, AdaptiveTranscriptColor>, TranscriptSystemColor)] = [
			(\.background, .textBackground),
			(\.primaryText, .label),
			(\.secondaryText, .secondaryLabel),
			(\.timestampText, .secondaryLabel),
			(\.eventText, .secondaryLabel),
			(\.link, .link),
			(\.highlightBackground, .findHighlight),
			(\.highlightText, .textOnFindHighlight),
			(\.bubbleOutgoing, .accentTint),
			(\.unreadMarker, .red),
			(\.chromeBackground, .textBackground),
		]
		for (role, system) in followed {
			palette[keyPath: role] = AdaptiveTranscriptColor(system: system, fallback: classic[keyPath: role])
		}
		return palette
	}()

	static func pair(
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

	static func color(_ value: UInt32) -> TranscriptThemeColor {
		TranscriptThemeColor(
			red: Double((value >> 16) & 0xFF) / 255,
			green: Double((value >> 8) & 0xFF) / 255,
			blue: Double(value & 0xFF) / 255
		)
	}

	private struct FormatProbe: Decodable {
		let formatVersion: Int
	}

	/** The one way a stored or imported property list becomes a theme: decode,
	 upgrade a version-3 or version-4 document, refuse any other version this
	 build does not write, and refuse anything the renderer could not draw. */
	static func decoded(from data: Data) throws -> Self {
		let decoder = PropertyListDecoder()
		if (try? decoder.decode(FormatProbe.self, from: data))?.formatVersion == 3 {
			decoder.userInfo[.transcriptThemeChromeFallsBackToBackground] = true
		}

		var decoded: Self
		do {
			decoded = try decoder.decode(Self.self, from: data)
		} catch {
			throw TranscriptThemeCodingError.invalidDocument
		}

		if upgradableFormatVersions.contains(decoded.formatVersion) {
			decoded.formatVersion = currentFormatVersion
			if decoded.palette == .classic {
				decoded.palette = defaultPalette
			}
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
