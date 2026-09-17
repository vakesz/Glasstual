// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
import Foundation

/** A colour in OKLCH, the polar form of OKLab, converted to sRGB the way the
 CSS Color 4 specification describes. Chroma is reduced until the colour fits
 the sRGB gamut, which keeps the lightness the caller asked for. */
nonisolated struct OKLCHColor {
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
