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

public nonisolated extension NSColor {
	private static func calibratedRGB(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat) -> NSColor {
		NSColor.textual_calibratedColor(red: red, green: green, blue: blue, alpha: 1.0)
	}

	/** Stored rather than computed: this used to reparse 83 hexadecimal literals
	 on every read, and it is read once per rendered colour code. */
	static let formatterColors: [NSColor] = [
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

	class var formatterWhiteColor: NSColor {
		calibratedRGB(1.00, 1.00, 1.00)
	}

	class var formatterBlackColor: NSColor {
		calibratedRGB(0.00, 0.00, 0.00)
	}

	class var formatterNavyBlueColor: NSColor {
		calibratedRGB(0.04, 0.00, 0.52)
	}

	class var formatterDarkGreenColor: NSColor {
		calibratedRGB(0.00, 0.54, 0.08)
	}

	class var formatterRedColor: NSColor {
		calibratedRGB(1.00, 0.05, 0.04)
	}

	class var formatterBrownColor: NSColor {
		calibratedRGB(0.55, 0.02, 0.02)
	}

	class var formatterPurpleColor: NSColor {
		calibratedRGB(0.55, 0.00, 0.53)
	}

	class var formatterOrangeColor: NSColor {
		calibratedRGB(1.00, 0.54, 0.09)
	}

	class var formatterYellowColor: NSColor {
		calibratedRGB(1.00, 1.00, 0.15)
	}

	class var formatterLimeGreenColor: NSColor {
		calibratedRGB(0.00, 1.00, 0.15)
	}

	class var formatterTealColor: NSColor {
		calibratedRGB(0.00, 0.53, 0.53)
	}

	class var formatterAquaCyanColor: NSColor {
		calibratedRGB(0.00, 1.00, 1.00)
	}

	class var formatterLightBlueColor: NSColor {
		calibratedRGB(0.07, 0.00, 0.98)
	}

	class var formatterFuchsiaPinkColor: NSColor {
		calibratedRGB(1.00, 0.00, 0.98)
	}

	class var formatterNormalGrayColor: NSColor {
		calibratedRGB(0.53, 0.53, 0.53)
	}

	class var formatterLightGrayColor: NSColor {
		calibratedRGB(0.80, 0.80, 0.80)
	}
}
