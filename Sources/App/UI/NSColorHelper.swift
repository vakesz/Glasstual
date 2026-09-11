/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 *********************************************************************** */

import AppKit
import CocoaExtensions

public extension NSColor {
	private nonisolated static func calibratedRGB( // nonisolated: pure
		_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat
	) -> NSColor {
		NSColor.textual_calibratedColor(red: red, green: green, blue: blue, alpha: 1.0)
	}

	/** Stored rather than computed: this used to reparse 83 hexadecimal literals
	 on every read, and it is read once per rendered colour code. */
	nonisolated static let formatterColors: [NSColor] = [ // nonisolated: let
		formatterWhiteColor,
		formatterBlackColor,
		formatterNavyBlueColor,
		formatterDarkGreenColor,
		formatterRedColor,
		formatterBrownColor,
		formatterPurpleColor,
		formatterOrangeColor,
		formatterYellowColor,
		formatterLimeGreenColor,
		formatterTealColor,
		formatterAquaCyanColor,
		formatterLightBlueColor,
		formatterFuchsiaPinkColor,
		formatterNormalGrayColor,
		formatterLightGrayColor,
		NSColor.textual_color(hexadecimalValue: "#470000")!,
		NSColor.textual_color(hexadecimalValue: "#472100")!,
		NSColor.textual_color(hexadecimalValue: "#474700")!,
		NSColor.textual_color(hexadecimalValue: "#324700")!,
		NSColor.textual_color(hexadecimalValue: "#004700")!,
		NSColor.textual_color(hexadecimalValue: "#00472c")!,
		NSColor.textual_color(hexadecimalValue: "#004747")!,
		NSColor.textual_color(hexadecimalValue: "#002747")!,
		NSColor.textual_color(hexadecimalValue: "#000047")!,
		NSColor.textual_color(hexadecimalValue: "#2e0047")!,
		NSColor.textual_color(hexadecimalValue: "#470047")!,
		NSColor.textual_color(hexadecimalValue: "#47002a")!,
		NSColor.textual_color(hexadecimalValue: "#740000")!,
		NSColor.textual_color(hexadecimalValue: "#743a00")!,
		NSColor.textual_color(hexadecimalValue: "#747400")!,
		NSColor.textual_color(hexadecimalValue: "#517400")!,
		NSColor.textual_color(hexadecimalValue: "#007400")!,
		NSColor.textual_color(hexadecimalValue: "#007449")!,
		NSColor.textual_color(hexadecimalValue: "#007474")!,
		NSColor.textual_color(hexadecimalValue: "#004074")!,
		NSColor.textual_color(hexadecimalValue: "#000074")!,
		NSColor.textual_color(hexadecimalValue: "#4b0074")!,
		NSColor.textual_color(hexadecimalValue: "#740074")!,
		NSColor.textual_color(hexadecimalValue: "#740045")!,
		NSColor.textual_color(hexadecimalValue: "#b50000")!,
		NSColor.textual_color(hexadecimalValue: "#b56300")!,
		NSColor.textual_color(hexadecimalValue: "#b5b500")!,
		NSColor.textual_color(hexadecimalValue: "#7db500")!,
		NSColor.textual_color(hexadecimalValue: "#00b500")!,
		NSColor.textual_color(hexadecimalValue: "#00b571")!,
		NSColor.textual_color(hexadecimalValue: "#00b5b5")!,
		NSColor.textual_color(hexadecimalValue: "#0063b5")!,
		NSColor.textual_color(hexadecimalValue: "#0000b5")!,
		NSColor.textual_color(hexadecimalValue: "#7500b5")!,
		NSColor.textual_color(hexadecimalValue: "#b500b5")!,
		NSColor.textual_color(hexadecimalValue: "#b5006b")!,
		NSColor.textual_color(hexadecimalValue: "#ff0000")!,
		NSColor.textual_color(hexadecimalValue: "#ff8c00")!,
		NSColor.textual_color(hexadecimalValue: "#ffff00")!,
		NSColor.textual_color(hexadecimalValue: "#b2ff00")!,
		NSColor.textual_color(hexadecimalValue: "#00ff00")!,
		NSColor.textual_color(hexadecimalValue: "#00ffa0")!,
		NSColor.textual_color(hexadecimalValue: "#00ffff")!,
		NSColor.textual_color(hexadecimalValue: "#008cff")!,
		NSColor.textual_color(hexadecimalValue: "#0000ff")!,
		NSColor.textual_color(hexadecimalValue: "#a500ff")!,
		NSColor.textual_color(hexadecimalValue: "#ff00ff")!,
		NSColor.textual_color(hexadecimalValue: "#ff0098")!,
		NSColor.textual_color(hexadecimalValue: "#ff5959")!,
		NSColor.textual_color(hexadecimalValue: "#ffb459")!,
		NSColor.textual_color(hexadecimalValue: "#ffff71")!,
		NSColor.textual_color(hexadecimalValue: "#cfff60")!,
		NSColor.textual_color(hexadecimalValue: "#6fff6f")!,
		NSColor.textual_color(hexadecimalValue: "#65ffc9")!,
		NSColor.textual_color(hexadecimalValue: "#6dffff")!,
		NSColor.textual_color(hexadecimalValue: "#59b4ff")!,
		NSColor.textual_color(hexadecimalValue: "#5959ff")!,
		NSColor.textual_color(hexadecimalValue: "#c459ff")!,
		NSColor.textual_color(hexadecimalValue: "#ff66ff")!,
		NSColor.textual_color(hexadecimalValue: "#ff59bc")!,
		NSColor.textual_color(hexadecimalValue: "#ff9c9c")!,
		NSColor.textual_color(hexadecimalValue: "#ffd39c")!,
		NSColor.textual_color(hexadecimalValue: "#ffff9c")!,
		NSColor.textual_color(hexadecimalValue: "#e2ff9c")!,
		NSColor.textual_color(hexadecimalValue: "#9cff9c")!,
		NSColor.textual_color(hexadecimalValue: "#9cffdb")!,
		NSColor.textual_color(hexadecimalValue: "#9cffff")!,
		NSColor.textual_color(hexadecimalValue: "#9cd3ff")!,
		NSColor.textual_color(hexadecimalValue: "#9c9cff")!,
		NSColor.textual_color(hexadecimalValue: "#dc9cff")!,
		NSColor.textual_color(hexadecimalValue: "#ff9cff")!,
		NSColor.textual_color(hexadecimalValue: "#ff94d3")!,
		NSColor.textual_color(hexadecimalValue: "#000000")!,
		NSColor.textual_color(hexadecimalValue: "#131313")!,
		NSColor.textual_color(hexadecimalValue: "#282828")!,
		NSColor.textual_color(hexadecimalValue: "#363636")!,
		NSColor.textual_color(hexadecimalValue: "#4d4d4d")!,
		NSColor.textual_color(hexadecimalValue: "#656565")!,
		NSColor.textual_color(hexadecimalValue: "#818181")!,
		NSColor.textual_color(hexadecimalValue: "#9f9f9f")!,
		NSColor.textual_color(hexadecimalValue: "#bcbcbc")!,
		NSColor.textual_color(hexadecimalValue: "#e2e2e2")!,
		NSColor.textual_color(hexadecimalValue: "#ffffff")!,
	]

	nonisolated class var formatterWhiteColor: NSColor { // nonisolated: pure
		calibratedRGB(1.00, 1.00, 1.00)
	}

	nonisolated class var formatterBlackColor: NSColor { // nonisolated: pure
		calibratedRGB(0.00, 0.00, 0.00)
	}

	nonisolated class var formatterNavyBlueColor: NSColor { // nonisolated: pure
		calibratedRGB(0.04, 0.00, 0.52)
	}

	nonisolated class var formatterDarkGreenColor: NSColor { // nonisolated: pure
		calibratedRGB(0.00, 0.54, 0.08)
	}

	nonisolated class var formatterRedColor: NSColor { // nonisolated: pure
		calibratedRGB(1.00, 0.05, 0.04)
	}

	nonisolated class var formatterBrownColor: NSColor { // nonisolated: pure
		calibratedRGB(0.55, 0.02, 0.02)
	}

	nonisolated class var formatterPurpleColor: NSColor { // nonisolated: pure
		calibratedRGB(0.55, 0.00, 0.53)
	}

	nonisolated class var formatterOrangeColor: NSColor { // nonisolated: pure
		calibratedRGB(1.00, 0.54, 0.09)
	}

	nonisolated class var formatterYellowColor: NSColor { // nonisolated: pure
		calibratedRGB(1.00, 1.00, 0.15)
	}

	nonisolated class var formatterLimeGreenColor: NSColor { // nonisolated: pure
		calibratedRGB(0.00, 1.00, 0.15)
	}

	nonisolated class var formatterTealColor: NSColor { // nonisolated: pure
		calibratedRGB(0.00, 0.53, 0.53)
	}

	nonisolated class var formatterAquaCyanColor: NSColor { // nonisolated: pure
		calibratedRGB(0.00, 1.00, 1.00)
	}

	nonisolated class var formatterLightBlueColor: NSColor { // nonisolated: pure
		calibratedRGB(0.07, 0.00, 0.98)
	}

	nonisolated class var formatterFuchsiaPinkColor: NSColor { // nonisolated: pure
		calibratedRGB(1.00, 0.00, 0.98)
	}

	nonisolated class var formatterNormalGrayColor: NSColor { // nonisolated: pure
		calibratedRGB(0.53, 0.53, 0.53)
	}

	nonisolated class var formatterLightGrayColor: NSColor { // nonisolated: pure
		calibratedRGB(0.80, 0.80, 0.80)
	}
}

/** Legibility, as WCAG measures it.

 The avatar picks the letter to draw on its fill with this, and three test
 suites check palettes and generated colours against it. Each had written out
 the same two formulas, and two of them had reached into `MemberAvatar` for the
 first — a view type is not where a colour-space measurement belongs. */
public extension NSColor {
	/** The relative luminance of this colour: how bright it reads, not how
	 bright its components are. A pattern or catalog colour that cannot be
	 resolved into sRGB is measured as it stands, which is the best available
	 answer rather than a refusal. */
	nonisolated var relativeLuminance: Double { // nonisolated: pure
		let color = usingColorSpace(.sRGB) ?? self
		func channel(_ value: CGFloat) -> Double {
			let component = Double(value)
			return component <= 0.03928 ? component / 12.92 : pow((component + 0.055) / 1.055, 2.4)
		}

		return 0.2126 * channel(color.redComponent) + 0.7152 * channel(color.greenComponent)
			+ 0.0722 * channel(color.blueComponent)
	}

	/// The WCAG contrast ratio between this colour and `other`, from 1:1 for
	/// two colours that read alike to 21:1 for black on white. Symmetric: the
	/// lighter of the two is always the numerator.
	nonisolated func contrastRatio(against other: NSColor) -> Double { // nonisolated: pure
		let first = relativeLuminance
		let second = other.relativeLuminance
		return (max(first, second) + 0.05) / (min(first, second) + 0.05)
	}
}

/** A colour in OKLCH, the polar form of OKLab, converted to sRGB the way the
 CSS Color 4 specification describes. Chroma is reduced until the colour fits
 the sRGB gamut, which keeps the lightness the caller asked for. */
nonisolated struct OKLCHColor { // nonisolated: value
	var lightness: Double
	var chroma: Double
	/// Degrees.
	var hue: Double

	var nsColor: NSColor {
		/* The hue fixes the direction in the a/b plane, and the search below
		 only shortens the vector along it, so the two transcendentals are
		 computed once instead of once per step. */
		let radians = hue * .pi / 180
		let unitA = cos(radians)
		let unitB = sin(radians)
		var chroma = chroma
		var components = linearSRGB(labA: unitA * chroma, labB: unitB * chroma)
		while chroma > 0, components.contains(where: { $0 < -0.0005 || $0 > 1.0005 }) {
			chroma = max(0, chroma - 0.005)
			components = linearSRGB(labA: unitA * chroma, labB: unitB * chroma)
		}
		let encoded = components.map(Self.encodeSRGB)
		return NSColor(srgbRed: encoded[0], green: encoded[1], blue: encoded[2], alpha: 1)
	}

	private func linearSRGB(labA: Double, labB: Double) -> [Double] {
		let longCone = lightness + 0.396_337_777_4 * labA + 0.215_803_757_3 * labB
		let mediumCone = lightness - 0.105_561_345_8 * labA - 0.063_854_172_8 * labB
		let shortCone = lightness - 0.089_484_177_5 * labA - 1.291_485_548_0 * labB
		let longCubed = longCone * longCone * longCone
		let mediumCubed = mediumCone * mediumCone * mediumCone
		let shortCubed = shortCone * shortCone * shortCone
		return [
			4.076_741_662_1 * longCubed - 3.307_711_591_3 * mediumCubed + 0.230_969_929_2 * shortCubed,
			-1.268_438_004_6 * longCubed + 2.609_757_401_1 * mediumCubed - 0.341_319_396_5 * shortCubed,
			-0.004_196_086_3 * longCubed - 0.703_418_614_8 * mediumCubed + 1.707_614_701_0 * shortCubed,
		]
	}

	private static func encodeSRGB(_ value: Double) -> Double {
		let clamped = min(1, max(0, value))
		return clamped <= 0.003_130_8 ? clamped * 12.92 : 1.055 * pow(clamped, 1 / 2.4) - 0.055
	}
}
