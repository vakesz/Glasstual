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

	init(lightness: Double, chroma: Double, hue: Double) {
		self.lightness = lightness
		self.chroma = chroma
		self.hue = hue
	}

	/// The OKLCH form of an sRGB colour with components from 0 to 255.
	init(red: UInt8, green: UInt8, blue: UInt8) {
		let linear = [red, green, blue].map { Self.decodeSRGB(Double($0) / 255) }
		let longCone = cbrt(0.412_221_470_8 * linear[0] + 0.536_332_536_3 * linear[1] + 0.051_445_992_9 * linear[2])
		let mediumCone = cbrt(0.211_903_498_2 * linear[0] + 0.680_699_545_1 * linear[1] + 0.107_396_956_6 * linear[2])
		let shortCone = cbrt(0.088_302_461_9 * linear[0] + 0.281_718_837_6 * linear[1] + 0.629_978_700_5 * linear[2])
		let labA = 1.977_998_495_1 * longCone - 2.428_592_205_0 * mediumCone + 0.450_593_709_9 * shortCone
		let labB = 0.025_904_037_1 * longCone + 0.782_771_766_2 * mediumCone - 0.808_675_766_0 * shortCone
		lightness = 0.210_454_255_3 * longCone + 0.793_617_785_0 * mediumCone - 0.004_072_046_8 * shortCone
		chroma = (labA * labA + labB * labB).squareRoot()
		let degrees = atan2(labB, labA) * 180 / .pi
		hue = degrees < 0 ? degrees + 360 : degrees
	}

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

	private static func decodeSRGB(_ value: Double) -> Double {
		value <= 0.040_45 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
	}

	private static func encodeSRGB(_ value: Double) -> Double {
		let clamped = min(1, max(0, value))
		return clamped <= 0.003_130_8 ? clamped * 12.92 : 1.055 * pow(clamped, 1 / 2.4) - 0.055
	}
}
