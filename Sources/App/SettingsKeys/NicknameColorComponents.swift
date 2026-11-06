// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit

/// A pinned nickname colour, as it is written to the defaults store: sRGB
/// components a plist editor can read, rather than an `NSKeyedArchiver` blob.
nonisolated struct NicknameColorComponents: Codable, Equatable, Sendable {
	var red: Double
	var green: Double
	var blue: Double
	var alpha: Double

	/// `nil` for a catalog or pattern colour, which has no components to ask
	/// for without raising an uncatchable exception.
	init?(_ color: NSColor) {
		guard let color = color.usingColorSpace(.sRGB) else {
			return nil
		}

		red = color.redComponent
		green = color.greenComponent
		blue = color.blueComponent
		alpha = color.alphaComponent
	}

	init(red: Double, green: Double, blue: Double, alpha: Double) {
		self.red = red
		self.green = green
		self.blue = blue
		self.alpha = alpha
	}

	private enum StoredKey {
		static let red = "red"
		static let green = "green"
		static let blue = "blue"
		static let alpha = "alpha"
	}

	/// Reads back the plist dictionary `storedValue` writes.
	init?(stored value: Any) {
		guard let dictionary = value as? [String: Double],
		      let red = dictionary[StoredKey.red],
		      let green = dictionary[StoredKey.green],
		      let blue = dictionary[StoredKey.blue]
		else {
			return nil
		}

		self.init(
			red: red,
			green: green,
			blue: blue,
			alpha: dictionary[StoredKey.alpha] ?? 1
		)
	}

	var storedValue: [String: Double] {
		[
			StoredKey.red: red,
			StoredKey.green: green,
			StoredKey.blue: blue,
			StoredKey.alpha: alpha,
		]
	}

	var color: NSColor {
		NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
	}
}
