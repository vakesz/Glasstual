/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import AppKit
import CocoaExtensions
import Foundation
@testable import Glasstual
import Testing

@MainActor
@Suite("Nickname color styles")
struct IRCUserNicknameColorStyleGeneratorTests {
	/// The hash is what decides a nickname's color, so a change repaints every
	/// conversation the user has ever seen.
	@Test("The hash still reads the MD5 digest in the legacy byte order")
	func hashRemainsCompatibleWithLegacyMD5ByteOrder() {
		let hash = UserNicknameColorStyleGenerator.hash(for: "alice")

		#expect(hash.uint32Value == 2_746_080_018)
	}

	@Test("The same nickname produces the same native colour")
	func colorIsStable() {
		let first = UserNicknameColorStyleGenerator.color(for: "alice")
		let second = UserNicknameColorStyleGenerator.color(for: "Alice")

		#expect(first.textualHexadecimalValue == second.textualHexadecimalValue)
	}

	/// The generated colour has to read against the theme ground it is drawn
	/// on: every hue, in both appearances. WCAG's 4.5:1 is the bar for text.
	@Test("Every generated colour contrasts with the default transcript ground")
	func colorsContrastWithDefaultGrounds() {
		/* Generated names only: a real one could carry a pinned colour on the
		 machine running the tests, and a pinned colour is the user's to choose. */
		let names = (0 ..< 400).map { "generated-\($0)" }
		let palette = TranscriptTheme.defaultPalette
		for isDark in [false, true] {
			let ground = isDark ? palette.background.dark.color : palette.background.light.color
			for name in names {
				let color = UserNicknameColorStyleGenerator.color(for: name, isDark: isDark)
				let ratio = color.contrastRatio(against: ground)
				#expect(ratio >= 4.5, "\(name) on \(isDark ? "dark" : "light") ground: \(ratio)")
			}
		}
	}

	@Test("OKLCH conversion reaches the sRGB anchors")
	func oklchAnchors() throws {
		let white = try #require(OKLCHColor(lightness: 1, chroma: 0, hue: 0).nsColor.usingColorSpace(.sRGB))
		for component in [white.redComponent, white.greenComponent, white.blueComponent] {
			#expect(abs(component - 1) < 0.01)
		}
		/* Neutral at L = 0.5 is 0.125 linear, which encodes to about 0.3885. */
		let grey = try #require(OKLCHColor(lightness: 0.5, chroma: 0, hue: 0).nsColor.usingColorSpace(.sRGB))
		for component in [grey.redComponent, grey.greenComponent, grey.blueComponent] {
			#expect(abs(component - 0.3885) < 0.005)
		}
	}

	@Test("A chroma the gamut cannot hold is reduced, and the lightness kept")
	func oklchGamutClipping() throws {
		let vivid = try #require(OKLCHColor(lightness: 0.8, chroma: 0.4, hue: 264).nsColor.usingColorSpace(.sRGB))
		for component in [vivid.redComponent, vivid.greenComponent, vivid.blueComponent] {
			#expect(component >= 0 && component <= 1)
		}
		let neutral = try #require(OKLCHColor(lightness: 0.8, chroma: 0, hue: 264).nsColor.usingColorSpace(.sRGB))
		#expect(abs(vivid.relativeLuminance - neutral.relativeLuminance) < 0.12)
	}

	@Test("The two appearances get different colours, and a pinned colour wins in both")
	func appearancesDifferAndOverridesWin() {
		/* A name no reader could have pinned, and the colour they might have
		 pinned for it put back afterwards rather than deleted: the store is the
		 developer's own, and clearing the key threw away whatever was there. */
		let nickname = "carol-\(UUID().uuidString.lowercased())"
		let dark = UserNicknameColorStyleGenerator.color(for: nickname, isDark: true)
		let light = UserNicknameColorStyleGenerator.color(for: nickname, isDark: false)
		#expect(dark.textualHexadecimalValue != light.textualHexadecimalValue)
		#expect(dark.relativeLuminance > light.relativeLuminance)

		let previous = UserNicknameColorStyleGenerator.nicknameColorStyleOverride(forKey: nickname)
		let pinned = NSColor(srgbRed: 0.2, green: 0.4, blue: 0.6, alpha: 1)
		UserNicknameColorStyleGenerator.setNicknameColorStyleOverride(pinned, forKey: nickname)
		defer { UserNicknameColorStyleGenerator.setNicknameColorStyleOverride(previous, forKey: nickname) }
		for isDark in [false, true] {
			let color = UserNicknameColorStyleGenerator.color(for: nickname.uppercased(), isDark: isDark)
			#expect(color.textualHexadecimalValue == pinned.textualHexadecimalValue)
		}
	}
}
