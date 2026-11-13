// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
import CocoaExtensions
@testable import Glasstual
import Testing

/// The default theme in the system's colours, the format that stores it and
/// the upgrade that moves a reader still on the old default onto it.
@MainActor
@Suite("Transcript system colours")
struct TranscriptSystemColorTests {
	private typealias Role = WritableKeyPath<TranscriptThemePalette, AdaptiveTranscriptColor>

	private static func encoded(_ theme: TranscriptTheme) throws -> Data {
		let encoder = PropertyListEncoder()
		encoder.outputFormat = .xml
		return try encoder.encode(theme)
	}

	/// A document as an older build wrote it: the theme at `version`, with no
	/// role following a system colour.
	private static func legacyDocument(
		_ theme: TranscriptTheme,
		version: Int,
		removingPaletteKey: String? = nil
	) throws -> Data {
		var document = try #require(
			PropertyListSerialization.propertyList(from: encoded(theme), format: nil) as? [String: Any]
		)
		var palette = try #require(document["palette"] as? [String: Any])
		if let removingPaletteKey {
			palette.removeValue(forKey: removingPaletteKey)
		}
		#expect(palette.values.allSatisfy { ($0 as? [String: Any])?["system"] == nil })
		document["palette"] = palette
		document["formatVersion"] = version
		return try PropertyListSerialization.data(fromPropertyList: document, format: .xml, options: 0)
	}

	private static func srgb(_ color: NSColor) -> NSColor {
		color.usingColorSpace(.sRGB) ?? color
	}

	/// `color` drawn over `ground`, which is what a translucent label reads as.
	private static func composited(_ color: NSColor, over ground: NSColor) -> NSColor {
		let top = srgb(color)
		let bottom = srgb(ground)
		let alpha = top.alphaComponent
		return NSColor(
			srgbRed: top.redComponent * alpha + bottom.redComponent * (1 - alpha),
			green: top.greenComponent * alpha + bottom.greenComponent * (1 - alpha),
			blue: top.blueComponent * alpha + bottom.blueComponent * (1 - alpha),
			alpha: 1
		)
	}

	private static func ratio(_ text: NSColor, on ground: NSColor) -> Double {
		composited(text, over: ground).contrastRatio(against: srgb(ground))
	}

	private static func appearance(isDark: Bool) throws -> NSAppearance {
		try #require(NSAppearance(named: isDark ? .darkAqua : .aqua))
	}

	/// The AppKit colour `color` names, read in `appearance`.
	private static func system(_ color: NSColor, in appearance: NSAppearance) -> TranscriptThemeColor? {
		var resolved: TranscriptThemeColor?
		appearance.performAsCurrentDrawingAppearance {
			resolved = TranscriptThemeColor(color)
		}
		return resolved
	}

	// MARK: - Format

	@Test("The default follows the system colours and keeps the format contract")
	func defaultFollowsSystemColours() {
		let palette = TranscriptTheme.defaultPalette
		let expected: [(Role, TranscriptSystemColor)] = [
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
		for (role, system) in expected {
			#expect(palette[keyPath: role].system == system)
		}
		#expect(palette.localNickname.system == nil)
		#expect(palette.remoteNickname.system == nil)
		#expect(TranscriptTheme.lines.isValid)
		#expect(TranscriptTheme.bubbles.isValid)
	}

	@Test("A role that follows the system round-trips through the XML property list")
	func systemRoleRoundTrips() throws {
		let data = try Self.encoded(.lines)
		let document = try #require(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
		let palette = try #require(document["palette"] as? [String: Any])
		let background = try #require(palette["background"] as? [String: Any])

		#expect(document["formatVersion"] as? Int == 5)
		#expect(background["system"] as? String == "textBackground")
		#expect(try TranscriptTheme.decoded(from: data) == .lines)
	}

	@Test("A system colour this build does not know is refused")
	func unknownSystemColourIsRefused() throws {
		var document = try #require(
			PropertyListSerialization.propertyList(from: Self.encoded(.lines), format: nil) as? [String: Any]
		)
		var palette = try #require(document["palette"] as? [String: Any])
		var link = try #require(palette["link"] as? [String: Any])
		link["system"] = "tertiarySparkle"
		palette["link"] = link
		document["palette"] = palette
		let data = try PropertyListSerialization.data(fromPropertyList: document, format: .xml, options: 0)

		#expect(throws: TranscriptThemeCodingError.invalidDocument) {
			try TranscriptTheme.decoded(from: data)
		}
	}

	@Test("Choosing a colour stops the role following the system")
	func choosingAColourStopsFollowing() {
		var palette = TranscriptTheme.defaultPalette
		let chosen = TranscriptThemeColor(red: 0.1, green: 0.2, blue: 0.3)
		palette.link.dark = chosen
		let resolved = TranscriptSystemColors([.link: TranscriptThemeColor(red: 0, green: 0, blue: 1)])

		#expect(palette.link.system == nil)
		#expect(palette.link.resolved(isDark: true, systemColors: resolved) == chosen.color)
	}

	// MARK: - Upgrade

	/// A reader who never chose a colour has the old default stored: it moves
	/// onto the system palette, keeping the layout and spacing it had.
	@Test("An older document on the old default palette upgrades to the system palette", arguments: [3, 4])
	func oldDefaultUpgrades(version: Int) throws {
		var legacy = TranscriptTheme.bubbles
		legacy.palette = .classic
		legacy.fontSize = 15
		let data = try Self.legacyDocument(
			legacy,
			version: version,
			removingPaletteKey: version == 3 ? "chromeBackground" : nil
		)

		let decoded = try TranscriptTheme.decoded(from: data)

		var expected = TranscriptTheme.bubbles
		expected.fontSize = 15
		#expect(decoded == expected)
		#expect(decoded.formatVersion == TranscriptTheme.currentFormatVersion)
	}

	@Test("An older document with a colour of its own keeps its palette")
	func customisedPaletteIsKept() throws {
		var legacy = TranscriptTheme.lines
		legacy.palette = .classic
		legacy.palette.link.light = TranscriptThemeColor(red: 0.5, green: 0.1, blue: 0.1)

		let decoded = try TranscriptTheme.decoded(from: Self.legacyDocument(legacy, version: 4))

		#expect(decoded.palette == legacy.palette)
		#expect(decoded.formatVersion == TranscriptTheme.currentFormatVersion)
	}

	@Test("An older document on a non-default preset keeps the preset", arguments: [
		TranscriptThemePreset.nord, .github, .solarized,
	])
	func presetIsKept(preset: TranscriptThemePreset) throws {
		let decoded = try TranscriptTheme.decoded(from: Self.legacyDocument(preset.theme(), version: 4))

		#expect(decoded == preset.theme())
	}

	@Test("A stored old default loads as the system default")
	func storedOldDefaultLoadsAsSystemDefault() throws {
		let fixture = try SettingsTransferFixture()
		defer { fixture.cleanUp() }
		var legacy = TranscriptTheme.lines
		legacy.palette = .classic
		try fixture.stores.set(.data(Self.legacyDocument(legacy, version: 4)), for: SettingsKeys.Theme.transcriptTheme)

		let store = ThemeStore(stores: fixture.stores)
		store.reload()

		#expect(store.theme == .lines)
	}

	// MARK: - Classic preset

	/// The palette the default shipped before this change, value for value:
	/// light, dark, increased-contrast light and increased-contrast dark.
	@Test("The Classic preset reproduces the former default palette exactly")
	func classicReproducesFormerDefault() {
		let expected: [(Role, [UInt32])] = [
			(\.background, [0xFFFFFF, 0x1E1E1E, 0xFFFFFF, 0x000000]),
			(\.primaryText, [0x202124, 0xF2F2F2, 0x000000, 0xFFFFFF]),
			(\.secondaryText, [0x5F5F64, 0xC2C2C6, 0x3A3A3C, 0xEBEBEF]),
			(\.timestampText, [0x68686D, 0xB6B6B9, 0x3A3A3C, 0xEBEBEF]),
			(\.eventText, [0x65656A, 0xB6B6B9, 0x2C2C2E, 0xEBEBF0]),
			(\.link, [0x0065D2, 0x81B9FF, 0x003E9C, 0xDEEDFF]),
			(\.localNickname, [0x006B3C, 0x67D99A, 0x004F2B, 0xC4F7DA]),
			(\.remoteNickname, [0x5B42A6, 0xBCAAFF, 0x3B2A80, 0xEEE9FF]),
			(\.highlightBackground, [0xFFF1B8, 0x5C4710, 0xFFE066, 0x634A00]),
			(\.highlightText, [0x202124, 0xFFFFFF, 0x000000, 0xFFFFFF]),
			(\.bubbleIncoming, [0xE9E9EB, 0x363638, 0xDCDCDE, 0x48484A]),
			(\.bubbleOutgoing, [0xD8ECFF, 0x164A73, 0xC3E1FF, 0x1A5080]),
			(\.unreadMarker, [0xD70015, 0xFF6961, 0xA30010, 0xFF8A80]),
			(\.failure, [0xB00020, 0xFF9A92, 0x8B0016, 0xFFE6E4]),
			(\.chromeBackground, [0xFFFFFF, 0x1E1E1E, 0xFFFFFF, 0x000000]),
		]
		#expect(expected.count == TranscriptThemePalette.roles.count)

		let theme = TranscriptThemePreset.classic.theme()
		for (role, values) in expected {
			let pair = theme.palette[keyPath: role]
			#expect(pair.system == nil)
			#expect(pair.light == TranscriptTheme.color(values[0]))
			#expect(pair.dark == TranscriptTheme.color(values[1]))
			#expect(pair.highContrastLight == TranscriptTheme.color(values[2]))
			#expect(pair.highContrastDark == TranscriptTheme.color(values[3]))
		}
		#expect(theme.name == "Classic")
		#expect(theme.layout == .lines)
		#expect(TranscriptThemePreset.allShippedThemes.contains(theme))
	}

	// MARK: - Resolution

	@Test("The default resolves to the system colours", arguments: [false, true])
	func defaultResolvesToSystemColours(isDark: Bool) throws {
		let appearance = try Self.appearance(isDark: isDark)
		let colors = TranscriptSystemColors.resolve(in: appearance, increasesContrast: false)
		let palette = TranscriptTheme.defaultPalette
		let expected: [(Role, NSColor)] = [
			(\.background, .textBackgroundColor),
			(\.primaryText, .labelColor),
			(\.secondaryText, .secondaryLabelColor),
			(\.link, .linkColor),
			(\.highlightBackground, .findHighlightColor),
			(\.unreadMarker, .systemRed),
		]

		for (role, system) in expected {
			let resolved = TranscriptThemeColor(palette[keyPath: role].resolved(isDark: isDark, systemColors: colors))
			#expect(resolved == Self.system(system, in: appearance))
		}
	}

	/** Increase Contrast draws the label colours opaque, and a role that
	 follows the system ignores the stored increased-contrast pair, which
	 belongs to the colours it stands in for. */
	@Test("Increased contrast draws the system colours at full strength", arguments: [false, true])
	func increasedContrastIsOpaque(isDark: Bool) throws {
		let appearance = try Self.appearance(isDark: isDark)
		let colors = TranscriptSystemColors.resolve(in: appearance, increasesContrast: true)
		let palette = TranscriptTheme.defaultPalette

		for role in [\TranscriptThemePalette.primaryText, \.secondaryText, \.timestampText, \.eventText] {
			let resolved = Self.srgb(palette[keyPath: role].resolved(
				isDark: isDark,
				increasesContrast: true,
				systemColors: colors
			))
			#expect(resolved.alphaComponent == 1)
		}

		let ground = palette.background.resolved(isDark: isDark, increasesContrast: true, systemColors: colors)
		let label = palette.primaryText.resolved(isDark: isDark, increasesContrast: true, systemColors: colors)
		#expect(TranscriptThemeColor(ground) == Self.system(.textBackgroundColor, in: appearance))
		#expect(Self.ratio(label, on: ground) >= 7)
	}

	@Test("The theme store resolves the default through the snapshot's system colours")
	func storeResolvesThroughSnapshot() throws {
		let fixture = try SettingsTransferFixture()
		let source = ThemeAppearanceSource()
		let store = source.makeStore(fixture)
		defer {
			fixture.cleanUp()
			AppServices.theme.appearanceDidChange()
		}
		let ground = TranscriptThemeColor(red: 0.2, green: 0.3, blue: 0.4)

		source.appearance.systemColors = TranscriptSystemColors([.textBackground: ground])
		store.appearanceDidChange()

		#expect(store.backgroundColor == ground.color)
		#expect(store.snapshot.systemColors == source.appearance.systemColors)
	}

	/// A new accent arrives as new system colours with the same appearance;
	/// the snapshot has to move so the transcript redraws.
	@Test("A change of system colours alone republishes the snapshot")
	func systemColourChangeRepublishes() throws {
		let fixture = try SettingsTransferFixture()
		let source = ThemeAppearanceSource()
		let store = source.makeStore(fixture)
		defer {
			fixture.cleanUp()
			AppServices.theme.appearanceDidChange()
		}
		source.appearance.systemColors = TranscriptSystemColors([.accentTint: TranscriptThemeColor(red: 0, green: 0, blue: 1)])
		store.appearanceDidChange()
		let before = store.snapshot

		source.appearance.systemColors = TranscriptSystemColors([.accentTint: TranscriptThemeColor(red: 1, green: 0, blue: 0)])
		store.appearanceDidChange()

		#expect(store.snapshot != before)
		#expect(LiveThemeSnapshot.current.systemColors == source.appearance.systemColors)
	}

	// MARK: - Contrast on the system ground

	/// The grounds the default draws on: the system text background, plain and
	/// with Increase Contrast's opaque labels.
	private static func systemGround(isDark: Bool, increasesContrast: Bool) throws -> NSColor {
		let colors = try TranscriptSystemColors.resolve(in: appearance(isDark: isDark), increasesContrast: increasesContrast)
		return TranscriptTheme.defaultPalette.background.resolved(
			isDark: isDark,
			increasesContrast: increasesContrast,
			systemColors: colors
		)
	}

	@Test("Generated nickname colours clear AA contrast on the system ground", arguments: [false, true])
	func nicknameColoursContrastWithSystemGround(isDark: Bool) throws {
		let names = (0 ..< 400).map { "generated-\($0)" }
		for increasesContrast in [false, true] {
			let ground = try Self.systemGround(isDark: isDark, increasesContrast: increasesContrast)
			for name in names {
				let ratio = NicknameColors.color(for: name, isDark: isDark).contrastRatio(against: Self.srgb(ground))
				#expect(ratio >= 4.5, "\(name) on the \(isDark ? "dark" : "light") system ground: \(ratio)")
			}
		}
	}

	@Test("Text roles clear their floors on the system ground", arguments: [false, true])
	func textRolesContrastWithSystemGround(isDark: Bool) throws {
		let colors = try TranscriptSystemColors.resolve(in: Self.appearance(isDark: isDark), increasesContrast: false)
		let palette = TranscriptTheme.defaultPalette
		let ground = palette.background.resolved(isDark: isDark, systemColors: colors)
		/* Body text holds WCAG AA. Secondary text holds the 3:1 Apple's own
		 secondary label holds, which is the large-text floor WCAG exempts
		 secondary content to. */
		let floors: [(role: Role, floor: Double)] = [
			(\.primaryText, 4.5),
			(\.link, 4.5),
			(\.localNickname, 4.5),
			(\.remoteNickname, 4.5),
			(\.failure, 4.5),
			(\.secondaryText, 3),
			(\.timestampText, 3),
			(\.eventText, 3),
		]
		for (role, floor) in floors {
			let ratio = Self.ratio(palette[keyPath: role].resolved(isDark: isDark, systemColors: colors), on: ground)
			#expect(ratio >= floor, "\(role) on the \(isDark ? "dark" : "light") system ground: \(ratio)")
		}

		let highlight = palette.highlightBackground.resolved(isDark: isDark, systemColors: colors)
		let highlighted = palette.highlightText.resolved(isDark: isDark, systemColors: colors)
		#expect(Self.ratio(highlighted, on: highlight) >= 7)
	}

	/// The outgoing bubble carries the reader's accent, whichever they chose:
	/// every system accent keeps label text at AA and links at 3:1 on it.
	@Test("Label text stays legible on the accent tint for every system accent", arguments: [false, true])
	func accentTintKeepsLabelsLegible(isDark: Bool) throws {
		let appearance = try Self.appearance(isDark: isDark)
		let accents: [NSColor] = [
			.systemBlue, .systemPurple, .systemPink, .systemRed, .systemOrange, .systemYellow, .systemGreen, .systemGray,
		]
		var measured: [(Double, Double)] = []
		appearance.performAsCurrentDrawingAppearance {
			let background = Self.srgb(.textBackgroundColor)
			for accent in accents {
				let tint = TranscriptSystemColor.accentTint(accent: accent, background: background, isDark: isDark)
				measured.append((Self.ratio(.labelColor, on: tint), Self.ratio(.linkColor, on: tint)))
			}
		}
		for (label, link) in measured {
			#expect(label >= 4.5)
			#expect(link >= 3)
		}
	}
}
