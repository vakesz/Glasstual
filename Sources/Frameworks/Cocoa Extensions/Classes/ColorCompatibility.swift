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

extension NSColor {
	@objc(calibratedColorWithRed:green:blue:alpha:)
	class func textual_calibratedColor(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) -> NSColor {
		NSColor(
			calibratedRed: normalized(red),
			green: normalized(green),
			blue: normalized(blue),
			alpha: normalized(alpha)
		)
	}

	@objc(calibratedDeviceColorWithRed:green:blue:alpha:)
	class func textual_calibratedDeviceColor(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) -> NSColor {
		NSColor(deviceRed: normalized(red), green: normalized(green), blue: normalized(blue), alpha: normalized(alpha))
	}

	@objc(hexadecimalValue)
	var textual_hexadecimalValue: String {
		let components = if colorSpace.colorSpaceModel == .gray {
			RGBComponents(red: whiteComponent, green: whiteComponent, blue: whiteComponent)
		} else {
			RGBComponents(red: redComponent, green: greenComponent, blue: blueComponent)
		}

		return String(
			format: "#%02X%02X%02X",
			UInt(components.red * 0xFF),
			UInt(components.green * 0xFF),
			UInt(components.blue * 0xFF)
		)
	}

	@objc(colorWithHexadecimalValue:)
	class func textual_color(hexadecimalValue value: String) -> NSColor? {
		let value = value.hasPrefix("#") ? String(value.dropFirst()) : value

		guard !value.isEmpty, value.count <= 8, value.count.isMultiple(of: 2),
		      var color = UInt64(value, radix: 16)
		else {
			return nil
		}

		if value.count < 8 {
			color = color << 8 | 0xFF
		}

		return textual_calibratedDeviceColor(
			red: CGFloat((color & 0xFF00_0000) >> 24),
			green: CGFloat((color & 0x00FF_0000) >> 16),
			blue: CGFloat((color & 0x0000_FF00) >> 8),
			alpha: CGFloat(color & 0x0000_00FF)
		)
	}

	private class func normalized(_ component: CGFloat) -> CGFloat {
		component > 1 ? component / 0xFF : component
	}
}

private struct RGBComponents {
	let red: CGFloat
	let green: CGFloat
	let blue: CGFloat
}
