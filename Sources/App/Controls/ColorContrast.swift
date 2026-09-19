// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

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

	/** Black or white, whichever can be read on this colour as a background.

	 WCAG's ratio is `(lighter + 0.05) / (darker + 0.05)`, so the two candidates
	 meet where `(Y + 0.05)² = 1.05 × 0.05` -- the threshold below. Either side
	 of it, the better of the two clears 4.5:1 on any background at all, a
	 pinned colour included. */
	nonisolated var legibleForeground: NSColor { // nonisolated: pure
		relativeLuminance > Self.blackOnBackgroundLuminance ? .black : .white
	}

	/// Where black overtakes white against a tinted ground.
	private nonisolated static let blackOnBackgroundLuminance = 0.1791

	/// The WCAG contrast ratio between this colour and `other`, from 1:1 for
	/// two colours that read alike to 21:1 for black on white. Symmetric: the
	/// lighter of the two is always the numerator.
	nonisolated func contrastRatio(against other: NSColor) -> Double { // nonisolated: pure
		let first = relativeLuminance
		let second = other.relativeLuminance
		return (max(first, second) + 0.05) / (min(first, second) + 0.05)
	}
}
