/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2010 - 2018 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
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
 *  * Neither the name of Textual, "Codeux Software, LLC", nor the
 *    names of its contributors may be used to endorse or promote products
 *    derived from this software without specific prior written permission.
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
import CocoaExtensions

/** A colour preference, stored as an archived `NSColor` because that is the
 format the colour wells in the preferences nib have always written.

 Holding the components rather than the archived bytes keeps the declared
 default comparable: two archives of the same colour are not byte-identical
 across releases, so a drift check against the checked-in plist has to compare
 colours, not `Data`. */
public nonisolated struct PreferenceColor: PreferenceValue { // nonisolated: value
	public let red: Double
	public let green: Double
	public let blue: Double
	public let alpha: Double

	public init(red: Double, green: Double, blue: Double, alpha: Double = 1.0) {
		self.red = red
		self.green = green
		self.blue = blue
		self.alpha = alpha
	}

	/// `nil` for a colour with no RGB representation, such as a pattern colour.
	public init?(_ color: NSColor) {
		guard let converted = color.usingColorSpace(.genericRGB) else {
			return nil
		}

		self.init(
			red: converted.redComponent,
			green: converted.greenComponent,
			blue: converted.blueComponent,
			alpha: converted.alphaComponent
		)
	}

	public var color: NSColor {
		NSColor(calibratedRed: red, green: green, blue: blue, alpha: alpha)
	}

	public static func preferenceValue(from object: Any) -> PreferenceColor? {
		guard let data = object as? Data,
		      let color = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: data)
		else {
			return nil
		}

		return PreferenceColor(color)
	}

	public var preferenceObject: Any {
		(try? NSKeyedArchiver.archivedData(withRootObject: color, requiringSecureCoding: true)) ?? Data()
	}
}

public nonisolated extension TextualUserDefaults { // nonisolated: pure
	/// The stored colour, or the key's declared default when nothing is stored.
	func color(for key: PreferenceKey<PreferenceColor>) -> NSColor {
		self[key].color
	}

	/// The stored colour, or `nil` when the user has not chosen one — for the
	/// wells whose "unset" state means "let the appearance decide".
	func storedColor(for key: PreferenceKey<PreferenceColor>) -> NSColor? {
		self[stored: key]?.color
	}

	func setColor(_ color: NSColor?, for key: PreferenceKey<PreferenceColor>) {
		guard let color, let value = PreferenceColor(color) else {
			removeValue(for: key)
			return
		}

		self[key] = value
	}
}
