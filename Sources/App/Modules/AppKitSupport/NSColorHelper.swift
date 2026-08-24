/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \\ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\\___/_/\\_\\__|\\__,_|\\__,_|_|
 *
 * Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 *********************************************************************** */

import AppKit

public extension NSColor {
	private static func calibratedRGB(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat) -> NSColor {
		NSColor.calibratedColor(withRed: red, green: green, blue: blue, alpha: 1.0)
	}

	@objc class var formatterColors: [NSColor] {
		[
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
			NSColor(hexadecimalValue: "#470000")!,
			NSColor(hexadecimalValue: "#472100")!,
			NSColor(hexadecimalValue: "#474700")!,
			NSColor(hexadecimalValue: "#324700")!,
			NSColor(hexadecimalValue: "#004700")!,
			NSColor(hexadecimalValue: "#00472c")!,
			NSColor(hexadecimalValue: "#004747")!,
			NSColor(hexadecimalValue: "#002747")!,
			NSColor(hexadecimalValue: "#000047")!,
			NSColor(hexadecimalValue: "#2e0047")!,
			NSColor(hexadecimalValue: "#470047")!,
			NSColor(hexadecimalValue: "#47002a")!,
			NSColor(hexadecimalValue: "#740000")!,
			NSColor(hexadecimalValue: "#743a00")!,
			NSColor(hexadecimalValue: "#747400")!,
			NSColor(hexadecimalValue: "#517400")!,
			NSColor(hexadecimalValue: "#007400")!,
			NSColor(hexadecimalValue: "#007449")!,
			NSColor(hexadecimalValue: "#007474")!,
			NSColor(hexadecimalValue: "#004074")!,
			NSColor(hexadecimalValue: "#000074")!,
			NSColor(hexadecimalValue: "#4b0074")!,
			NSColor(hexadecimalValue: "#740074")!,
			NSColor(hexadecimalValue: "#740045")!,
			NSColor(hexadecimalValue: "#b50000")!,
			NSColor(hexadecimalValue: "#b56300")!,
			NSColor(hexadecimalValue: "#b5b500")!,
			NSColor(hexadecimalValue: "#7db500")!,
			NSColor(hexadecimalValue: "#00b500")!,
			NSColor(hexadecimalValue: "#00b571")!,
			NSColor(hexadecimalValue: "#00b5b5")!,
			NSColor(hexadecimalValue: "#0063b5")!,
			NSColor(hexadecimalValue: "#0000b5")!,
			NSColor(hexadecimalValue: "#7500b5")!,
			NSColor(hexadecimalValue: "#b500b5")!,
			NSColor(hexadecimalValue: "#b5006b")!,
			NSColor(hexadecimalValue: "#ff0000")!,
			NSColor(hexadecimalValue: "#ff8c00")!,
			NSColor(hexadecimalValue: "#ffff00")!,
			NSColor(hexadecimalValue: "#b2ff00")!,
			NSColor(hexadecimalValue: "#00ff00")!,
			NSColor(hexadecimalValue: "#00ffa0")!,
			NSColor(hexadecimalValue: "#00ffff")!,
			NSColor(hexadecimalValue: "#008cff")!,
			NSColor(hexadecimalValue: "#0000ff")!,
			NSColor(hexadecimalValue: "#a500ff")!,
			NSColor(hexadecimalValue: "#ff00ff")!,
			NSColor(hexadecimalValue: "#ff0098")!,
			NSColor(hexadecimalValue: "#ff5959")!,
			NSColor(hexadecimalValue: "#ffb459")!,
			NSColor(hexadecimalValue: "#ffff71")!,
			NSColor(hexadecimalValue: "#cfff60")!,
			NSColor(hexadecimalValue: "#6fff6f")!,
			NSColor(hexadecimalValue: "#65ffc9")!,
			NSColor(hexadecimalValue: "#6dffff")!,
			NSColor(hexadecimalValue: "#59b4ff")!,
			NSColor(hexadecimalValue: "#5959ff")!,
			NSColor(hexadecimalValue: "#c459ff")!,
			NSColor(hexadecimalValue: "#ff66ff")!,
			NSColor(hexadecimalValue: "#ff59bc")!,
			NSColor(hexadecimalValue: "#ff9c9c")!,
			NSColor(hexadecimalValue: "#ffd39c")!,
			NSColor(hexadecimalValue: "#ffff9c")!,
			NSColor(hexadecimalValue: "#e2ff9c")!,
			NSColor(hexadecimalValue: "#9cff9c")!,
			NSColor(hexadecimalValue: "#9cffdb")!,
			NSColor(hexadecimalValue: "#9cffff")!,
			NSColor(hexadecimalValue: "#9cd3ff")!,
			NSColor(hexadecimalValue: "#9c9cff")!,
			NSColor(hexadecimalValue: "#dc9cff")!,
			NSColor(hexadecimalValue: "#ff9cff")!,
			NSColor(hexadecimalValue: "#ff94d3")!,
			NSColor(hexadecimalValue: "#000000")!,
			NSColor(hexadecimalValue: "#131313")!,
			NSColor(hexadecimalValue: "#282828")!,
			NSColor(hexadecimalValue: "#363636")!,
			NSColor(hexadecimalValue: "#4d4d4d")!,
			NSColor(hexadecimalValue: "#656565")!,
			NSColor(hexadecimalValue: "#818181")!,
			NSColor(hexadecimalValue: "#9f9f9f")!,
			NSColor(hexadecimalValue: "#bcbcbc")!,
			NSColor(hexadecimalValue: "#e2e2e2")!,
			NSColor(hexadecimalValue: "#ffffff")!,
		]
	}

	@objc class var formatterWhiteColor: NSColor {
		calibratedRGB(1.00, 1.00, 1.00)
	}

	@objc class var formatterBlackColor: NSColor {
		calibratedRGB(0.00, 0.00, 0.00)
	}

	@objc class var formatterNavyBlueColor: NSColor {
		calibratedRGB(0.04, 0.00, 0.52)
	}

	@objc class var formatterDarkGreenColor: NSColor {
		calibratedRGB(0.00, 0.54, 0.08)
	}

	@objc class var formatterRedColor: NSColor {
		calibratedRGB(1.00, 0.05, 0.04)
	}

	@objc class var formatterBrownColor: NSColor {
		calibratedRGB(0.55, 0.02, 0.02)
	}

	@objc class var formatterPurpleColor: NSColor {
		calibratedRGB(0.55, 0.00, 0.53)
	}

	@objc class var formatterOrangeColor: NSColor {
		calibratedRGB(1.00, 0.54, 0.09)
	}

	@objc class var formatterYellowColor: NSColor {
		calibratedRGB(1.00, 1.00, 0.15)
	}

	@objc class var formatterLimeGreenColor: NSColor {
		calibratedRGB(0.00, 1.00, 0.15)
	}

	@objc class var formatterTealColor: NSColor {
		calibratedRGB(0.00, 0.53, 0.53)
	}

	@objc class var formatterAquaCyanColor: NSColor {
		calibratedRGB(0.00, 1.00, 1.00)
	}

	@objc class var formatterLightBlueColor: NSColor {
		calibratedRGB(0.07, 0.00, 0.98)
	}

	@objc class var formatterFuchsiaPinkColor: NSColor {
		calibratedRGB(1.00, 0.00, 0.98)
	}

	@objc class var formatterNormalGrayColor: NSColor {
		calibratedRGB(0.53, 0.53, 0.53)
	}

	@objc class var formatterLightGrayColor: NSColor {
		calibratedRGB(0.80, 0.80, 0.80)
	}
}
