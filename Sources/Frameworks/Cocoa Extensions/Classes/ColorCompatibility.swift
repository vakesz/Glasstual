/* *********************************************************************
 *
 *         Copyright (c) 2015 - 2018 Codeux Software, LLC
 *     Please see ACKNOWLEDGEMENT for additional information.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 *
 *  * Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 *  * Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 *  * Neither the name of "Codeux Software, LLC", nor the names of its
 *    contributors may be used to endorse or promote products derived
 *    from this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED. IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
 * FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
 * OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
 * LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
 * OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
 * SUCH DAMAGE.
 *
 *********************************************************************** */

import AppKit
import os

private let colorLogger = Logger(
	subsystem: "com.codeux.frameworks.CocoaExtensions",
	category: "Color"
)

public extension NSColor {
	class func textual_calibratedColor(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) -> NSColor {
		NSColor(
			calibratedRed: normalized(red),
			green: normalized(green),
			blue: normalized(blue),
			alpha: normalized(alpha)
		)
	}

	class func textual_calibratedDeviceColor(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) -> NSColor {
		NSColor(deviceRed: normalized(red), green: normalized(green), blue: normalized(blue), alpha: normalized(alpha))
	}

	var textualHexadecimalValue: String {
		/* Asking a catalog or pattern colour for its components raises an
		 uncatchable exception, and an extended-range colour can report a
		 component outside 0...1. Convert first, clamp second. */
		guard let color = usingColorSpace(.sRGB) else {
			colorLogger.error("Could not convert a colour to sRGB for its hexadecimal value")

			return "#000000"
		}

		return String(
			format: "#%02X%02X%02X",
			NSColor.textualChannelByte(color.redComponent),
			NSColor.textualChannelByte(color.greenComponent),
			NSColor.textualChannelByte(color.blueComponent)
		)
	}

	/// A colour component as the byte it is written as. The clamp is what makes
	/// `UInt8` safe: an extended-range colour can report a component outside
	/// 0...1.
	private static func textualChannelByte(_ component: CGFloat) -> UInt8 {
		UInt8((min(max(component, 0), 1) * 0xFF).rounded())
	}

	class func textual_color(hexadecimalValue value: String) -> NSColor? {
		var value = value.hasPrefix("#") ? String(value.dropFirst()) : value

		/* CSS shorthand: #rgb and #rgba repeat each digit. */
		if value.count == 3 || value.count == 4 {
			value = String(value.flatMap { [$0, $0] })
		}

		guard value.count == 6 || value.count == 8, var color = UInt64(value, radix: 16) else {
			return nil
		}

		if value.count == 6 {
			color = color << 8 | 0xFF
		}

		/* Channels here are 0-255. The convenience initialiser's "is this
		 0-1 or 0-255?" heuristic reads a channel of exactly 1 as full
		 intensity, so build the components directly. */
		return NSColor(
			deviceRed: textualChannel(color >> 24),
			green: textualChannel(color >> 16),
			blue: textualChannel(color >> 8),
			alpha: textualChannel(color)
		)
	}

	private class func textualChannel(_ value: UInt64) -> CGFloat {
		CGFloat(value & 0xFF) / 0xFF
	}

	private class func normalized(_ component: CGFloat) -> CGFloat {
		component > 1 ? component / 0xFF : component
	}
}
