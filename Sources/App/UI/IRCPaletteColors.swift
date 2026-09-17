// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
import CocoaExtensions

extension NSColor {
	private nonisolated static func calibratedRGB( // nonisolated: pure
		_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat
	) -> NSColor {
		NSColor.calibratedColor(red: red, green: green, blue: blue, alpha: 1.0)
	}

	/** Stored rather than computed: this used to reparse 83 hexadecimal literals
	 on every read, and it is read once per rendered colour code. */
	nonisolated static let formatterColors: [NSColor] = [
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
		NSColor.color(hexadecimal: "#470000")!,
		NSColor.color(hexadecimal: "#472100")!,
		NSColor.color(hexadecimal: "#474700")!,
		NSColor.color(hexadecimal: "#324700")!,
		NSColor.color(hexadecimal: "#004700")!,
		NSColor.color(hexadecimal: "#00472c")!,
		NSColor.color(hexadecimal: "#004747")!,
		NSColor.color(hexadecimal: "#002747")!,
		NSColor.color(hexadecimal: "#000047")!,
		NSColor.color(hexadecimal: "#2e0047")!,
		NSColor.color(hexadecimal: "#470047")!,
		NSColor.color(hexadecimal: "#47002a")!,
		NSColor.color(hexadecimal: "#740000")!,
		NSColor.color(hexadecimal: "#743a00")!,
		NSColor.color(hexadecimal: "#747400")!,
		NSColor.color(hexadecimal: "#517400")!,
		NSColor.color(hexadecimal: "#007400")!,
		NSColor.color(hexadecimal: "#007449")!,
		NSColor.color(hexadecimal: "#007474")!,
		NSColor.color(hexadecimal: "#004074")!,
		NSColor.color(hexadecimal: "#000074")!,
		NSColor.color(hexadecimal: "#4b0074")!,
		NSColor.color(hexadecimal: "#740074")!,
		NSColor.color(hexadecimal: "#740045")!,
		NSColor.color(hexadecimal: "#b50000")!,
		NSColor.color(hexadecimal: "#b56300")!,
		NSColor.color(hexadecimal: "#b5b500")!,
		NSColor.color(hexadecimal: "#7db500")!,
		NSColor.color(hexadecimal: "#00b500")!,
		NSColor.color(hexadecimal: "#00b571")!,
		NSColor.color(hexadecimal: "#00b5b5")!,
		NSColor.color(hexadecimal: "#0063b5")!,
		NSColor.color(hexadecimal: "#0000b5")!,
		NSColor.color(hexadecimal: "#7500b5")!,
		NSColor.color(hexadecimal: "#b500b5")!,
		NSColor.color(hexadecimal: "#b5006b")!,
		NSColor.color(hexadecimal: "#ff0000")!,
		NSColor.color(hexadecimal: "#ff8c00")!,
		NSColor.color(hexadecimal: "#ffff00")!,
		NSColor.color(hexadecimal: "#b2ff00")!,
		NSColor.color(hexadecimal: "#00ff00")!,
		NSColor.color(hexadecimal: "#00ffa0")!,
		NSColor.color(hexadecimal: "#00ffff")!,
		NSColor.color(hexadecimal: "#008cff")!,
		NSColor.color(hexadecimal: "#0000ff")!,
		NSColor.color(hexadecimal: "#a500ff")!,
		NSColor.color(hexadecimal: "#ff00ff")!,
		NSColor.color(hexadecimal: "#ff0098")!,
		NSColor.color(hexadecimal: "#ff5959")!,
		NSColor.color(hexadecimal: "#ffb459")!,
		NSColor.color(hexadecimal: "#ffff71")!,
		NSColor.color(hexadecimal: "#cfff60")!,
		NSColor.color(hexadecimal: "#6fff6f")!,
		NSColor.color(hexadecimal: "#65ffc9")!,
		NSColor.color(hexadecimal: "#6dffff")!,
		NSColor.color(hexadecimal: "#59b4ff")!,
		NSColor.color(hexadecimal: "#5959ff")!,
		NSColor.color(hexadecimal: "#c459ff")!,
		NSColor.color(hexadecimal: "#ff66ff")!,
		NSColor.color(hexadecimal: "#ff59bc")!,
		NSColor.color(hexadecimal: "#ff9c9c")!,
		NSColor.color(hexadecimal: "#ffd39c")!,
		NSColor.color(hexadecimal: "#ffff9c")!,
		NSColor.color(hexadecimal: "#e2ff9c")!,
		NSColor.color(hexadecimal: "#9cff9c")!,
		NSColor.color(hexadecimal: "#9cffdb")!,
		NSColor.color(hexadecimal: "#9cffff")!,
		NSColor.color(hexadecimal: "#9cd3ff")!,
		NSColor.color(hexadecimal: "#9c9cff")!,
		NSColor.color(hexadecimal: "#dc9cff")!,
		NSColor.color(hexadecimal: "#ff9cff")!,
		NSColor.color(hexadecimal: "#ff94d3")!,
		NSColor.color(hexadecimal: "#000000")!,
		NSColor.color(hexadecimal: "#131313")!,
		NSColor.color(hexadecimal: "#282828")!,
		NSColor.color(hexadecimal: "#363636")!,
		NSColor.color(hexadecimal: "#4d4d4d")!,
		NSColor.color(hexadecimal: "#656565")!,
		NSColor.color(hexadecimal: "#818181")!,
		NSColor.color(hexadecimal: "#9f9f9f")!,
		NSColor.color(hexadecimal: "#bcbcbc")!,
		NSColor.color(hexadecimal: "#e2e2e2")!,
		NSColor.color(hexadecimal: "#ffffff")!,
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
