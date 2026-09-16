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

/** Legibility, as WCAG measures it.

 The avatar picks the letter to draw on its fill with this, and three test
 suites check palettes and generated colours against it. Each had written out
 the same two formulas, and two of them had reached into `MemberAvatar` for the
 first — a view type is not where a colour-space measurement belongs. */
extension NSColor {
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
