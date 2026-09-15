/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 *********************************************************************** */

import AppKit
import Foundation

/// A portable sRGB colour. Theme files use components rather than archived
/// `NSColor` objects so they remain readable and stable across macOS releases.
public nonisolated struct TranscriptThemeColor: Codable, Equatable, Sendable { // nonisolated: value
	public var red: Double
	public var green: Double
	public var blue: Double
	public var alpha: Double

	public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
		self.red = red
		self.green = green
		self.blue = blue
		self.alpha = alpha
	}

	public init?(_ color: NSColor) {
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

	public var color: NSColor {
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
public nonisolated struct AdaptiveTranscriptColor: Codable, Equatable, Sendable { // nonisolated: value
	public var light: TranscriptThemeColor {
		didSet { highContrastLight = nil }
	}

	public var dark: TranscriptThemeColor {
		didSet { highContrastDark = nil }
	}

	public private(set) var highContrastLight: TranscriptThemeColor?
	public private(set) var highContrastDark: TranscriptThemeColor?

	public init(light: TranscriptThemeColor, dark: TranscriptThemeColor) {
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

	public func resolved(isDark: Bool, increasesContrast: Bool = false) -> NSColor {
		let stronger = increasesContrast ? (isDark ? highContrastDark : highContrastLight) : nil
		return (stronger ?? (isDark ? dark : light)).color
	}

	/// Whether the two roles draw the same in ordinary contrast, which is what
	/// says a stored role is still the one the palette shipped with.
	func matchesOrdinaryColors(of other: Self) -> Bool {
		light == other.light && dark == other.dark
	}

	var isValid: Bool {
		light.isValid && dark.isValid
			&& highContrastLight?.isValid != false && highContrastDark?.isValid != false
	}
}

public nonisolated enum TranscriptThemeLayout: String, Codable, CaseIterable, Sendable { // nonisolated: value
	case lines
	case bubbles
}

/// Every colour the native transcript draws, named by purpose rather than by
/// where a former stylesheet happened to use it.
public nonisolated struct TranscriptThemePalette: Codable, Equatable, Sendable { // nonisolated: value
	public var background: AdaptiveTranscriptColor
	public var primaryText: AdaptiveTranscriptColor
	public var secondaryText: AdaptiveTranscriptColor
	/// The clock beside each line, quieter than the secondary text it used to
	/// share but still legible: the default is the quietest grey that keeps
	/// 4.5:1 against the default ground. Themes written before the role existed
	/// decode it as their secondary text.
	public var timestampText: AdaptiveTranscriptColor
	public var eventText: AdaptiveTranscriptColor
	public var link: AdaptiveTranscriptColor
	public var localNickname: AdaptiveTranscriptColor
	public var remoteNickname: AdaptiveTranscriptColor
	public var highlightBackground: AdaptiveTranscriptColor
	public var highlightText: AdaptiveTranscriptColor
	public var bubbleIncoming: AdaptiveTranscriptColor
	public var bubbleOutgoing: AdaptiveTranscriptColor
	public var unreadMarker: AdaptiveTranscriptColor
	public var failure: AdaptiveTranscriptColor

	public init(
		background: AdaptiveTranscriptColor,
		primaryText: AdaptiveTranscriptColor,
		secondaryText: AdaptiveTranscriptColor,
		timestampText: AdaptiveTranscriptColor,
		eventText: AdaptiveTranscriptColor,
		link: AdaptiveTranscriptColor,
		localNickname: AdaptiveTranscriptColor,
		remoteNickname: AdaptiveTranscriptColor,
		highlightBackground: AdaptiveTranscriptColor,
		highlightText: AdaptiveTranscriptColor,
		bubbleIncoming: AdaptiveTranscriptColor,
		bubbleOutgoing: AdaptiveTranscriptColor,
		unreadMarker: AdaptiveTranscriptColor,
		failure: AdaptiveTranscriptColor
	) {
		self.background = background
		self.primaryText = primaryText
		self.secondaryText = secondaryText
		self.timestampText = timestampText
		self.eventText = eventText
		self.link = link
		self.localNickname = localNickname
		self.remoteNickname = remoteNickname
		self.highlightBackground = highlightBackground
		self.highlightText = highlightText
		self.bubbleIncoming = bubbleIncoming
		self.bubbleOutgoing = bubbleOutgoing
		self.unreadMarker = unreadMarker
		self.failure = failure
	}

	/// Themes written before `timestampText` existed decode it as their
	/// secondary text, which is the colour their timestamps had.
	public init(from decoder: any Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)
		background = try container.decode(AdaptiveTranscriptColor.self, forKey: .background)
		primaryText = try container.decode(AdaptiveTranscriptColor.self, forKey: .primaryText)
		secondaryText = try container.decode(AdaptiveTranscriptColor.self, forKey: .secondaryText)
		timestampText = try container.decodeIfPresent(AdaptiveTranscriptColor.self, forKey: .timestampText)
			?? secondaryText
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
	}

	/// Every colour role, so a pass over the palette cannot miss one.
	static var roles: [WritableKeyPath<Self, AdaptiveTranscriptColor>] {
		[
			\.background, \.primaryText, \.secondaryText, \.timestampText, \.eventText, \.link,
			\.localNickname, \.remoteNickname, \.highlightBackground, \.highlightText,
			\.bubbleIncoming, \.bubbleOutgoing, \.unreadMarker, \.failure,
		]
	}

	/** Takes the increased-contrast variants version 3 added, for every role
	 still drawing the colour the shipped palette gave it.

	 A role somebody recoloured is left alone: their colour is the answer in
	 both contrast settings, and inventing a stronger one for it would draw
	 something they never chose. */
	mutating func adoptDefaultHighContrastVariants() {
		let defaults = TranscriptTheme.defaultPalette
		for role in Self.roles where self[keyPath: role].matchesOrdinaryColors(of: defaults[keyPath: role]) {
			self[keyPath: role] = defaults[keyPath: role]
		}
	}

	var isValid: Bool {
		Self.roles.allSatisfy { self[keyPath: $0].isValid }
	}
}

/// The one native transcript theme format. It is both the runtime model and
/// the payload written by Export Theme, avoiding adapters between preference,
/// file, and rendering representations.
public nonisolated struct TranscriptTheme: Codable, Equatable, Sendable { // nonisolated: value
	/// Version 2 replaced the `<>` around nicknames in the default format with
	/// a trailing colon; version 3 gave every colour role a variant for the
	/// system's increased-contrast setting. An older document is read and
	/// carried forward, see `migrated()`.
	public static let currentFormatVersion = 3
	public static let supportedFormatVersions = 1 ... currentFormatVersion

	public var formatVersion = currentFormatVersion
	public var name: String
	public var layout: TranscriptThemeLayout
	public var fontName: String
	public var fontSize: Double
	public var timestampFormat: String
	public var nicknameFormat: String
	public var lineSpacing: Double
	public var messageSpacing: Double
	public var horizontalPadding: Double
	public var palette: TranscriptThemePalette

	public init(
		name: String,
		layout: TranscriptThemeLayout,
		fontName: String = ".AppleSystemUIFont",
		fontSize: Double = 13,
		timestampFormat: String = "%H:%M:%S",
		/* The colon is what separates the nickname from the message: the
			renderer's gap alone reads as `12:34  @alice  hello`, three columns
			with nothing saying which one is the speaker. */
		nicknameFormat: String = "%@%n:",
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

	public static let lines = TranscriptTheme(
		name: "Lines",
		layout: .lines,
		palette: defaultPalette
	)

	public static let bubbles = TranscriptTheme(
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
	public static let defaultPalette = TranscriptThemePalette(
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

	/// The nickname format every version 1 theme shipped with.
	static let legacyBracketedNicknameFormat = "<%@%n>"

	/** An older document brought up to the current version.

	 The brackets were the version 1 default rather than a choice, so a version
	 1 theme still carrying them is read as asking for the current default; a
	 theme that has been through this once keeps whatever it says, brackets
	 included, because it is then version 2 and is not read this way again. A
	 version 2 palette carries no increased-contrast variants, so every role
	 still drawing what it shipped with takes the one that ships beside it now. */
	func migrated() -> Self {
		var theme = self
		if theme.formatVersion < 2, theme.nicknameFormat == Self.legacyBracketedNicknameFormat {
			theme.nicknameFormat = Self.lines.nicknameFormat
		}
		if theme.formatVersion < 3 {
			theme.palette.adoptDefaultHighContrastVariants()
		}
		theme.formatVersion = Self.currentFormatVersion
		return theme
	}

	/** One decoded document: the theme to draw with, and the format version the
	 file itself carried.

	 They differ exactly when `migrated()` moved the document forward, which is
	 what tells a caller to write the upgraded document back instead of
	 migrating the same file again at every launch. */
	public nonisolated struct Document: Equatable, Sendable { // nonisolated: value
		public let theme: TranscriptTheme
		public let formatVersion: Int

		public var wasMigrated: Bool {
			formatVersion != theme.formatVersion
		}
	}

	/** The one way a stored or imported property list becomes a theme: decode,
	 refuse a version this build does not know, carry an older one forward, and
	 refuse anything the renderer could not draw. */
	public static func decoded(from data: Data) throws -> Document {
		let decoded: Self
		do {
			decoded = try PropertyListDecoder().decode(Self.self, from: data)
		} catch {
			throw TranscriptThemeCodingError.invalidDocument
		}

		guard supportedFormatVersions.contains(decoded.formatVersion) else {
			throw TranscriptThemeCodingError.unsupportedVersion(decoded.formatVersion)
		}

		let theme = decoded.migrated()
		guard theme.isValid else {
			throw TranscriptThemeCodingError.invalidDocument
		}

		return Document(theme: theme, formatVersion: decoded.formatVersion)
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
public nonisolated enum TranscriptThemeCodingError: LocalizedError, Equatable, Sendable { // nonisolated: value
	case invalidDocument
	case unsupportedVersion(Int)

	public var errorDescription: String? {
		switch self {
		case .invalidDocument:
			TranscriptThemeStrings.invalidDocument
		case let .unsupportedVersion(version):
			TranscriptThemeStrings.unsupportedVersion(version)
		}
	}
}
