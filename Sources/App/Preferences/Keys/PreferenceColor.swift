// Copyright (c) 2010 - 2018 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
import CocoaExtensions
import os

private nonisolated let preferenceColorLogger = Logger(
	subsystem: Bundle.main.bundleIdentifier ?? "Glasstual",
	category: "Preferences"
)

/** A colour preference with a versioned Codable representation. Existing
 `NSColor` keyed archives remain readable when an older preference is loaded.

 Holding the components rather than the archived bytes keeps the declared
 default comparable after decoding: two legacy archives of the same colour
 need not contain identical bytes. */
nonisolated struct PreferenceColor: PreferenceValue, Codable {
	let red: Double
	let green: Double
	let blue: Double
	let alpha: Double

	init(red: Double, green: Double, blue: Double, alpha: Double = 1.0) {
		self.red = red
		self.green = green
		self.blue = blue
		self.alpha = alpha
	}

	/// `nil` for a colour with no RGB representation, such as a pattern colour.
	init?(_ color: NSColor) {
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

	var color: NSColor {
		NSColor(calibratedRed: red, green: green, blue: blue, alpha: alpha)
	}

	static func preferenceValue(from object: Any) -> PreferenceColor? {
		guard let data = object as? Data else { return nil }
		if let payload = try? PropertyListDecoder().decode(StoredColor.self, from: data) {
			guard payload.version == StoredColor.currentVersion,
			      [payload.color.red, payload.color.green, payload.color.blue, payload.color.alpha].allSatisfy(\.isFinite)
			else { return nil }
			return payload.color
		}
		guard let propertyList = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
		      propertyList["$archiver"] as? String == "NSKeyedArchiver",
		      let color = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: data)
		else {
			return nil
		}

		return PreferenceColor(color)
	}

	var preferenceObject: Any? {
		do {
			guard [red, green, blue, alpha].allSatisfy(\.isFinite) else { return nil }
			return try PropertyListEncoder().encode(StoredColor(color: self))
		} catch {
			/* Nothing is written for a colour that will not archive. The empty
			 `Data` this used to store read back as unarchivable, so the choice
			 was lost and the store held a blob that shadowed nothing. */
			preferenceColorLogger.error(
				"Could not archive a colour preference: \(error.localizedDescription, privacy: .public)"
			)

			return nil
		}
	}

	private struct StoredColor: Codable {
		static let currentVersion = 1
		var version = currentVersion
		let color: PreferenceColor
	}
}

nonisolated extension GlasstualUserDefaults { // nonisolated: guarded
	/// The stored colour, or the key's declared default when nothing is stored.
	func color(for key: PreferenceKey<PreferenceColor>) -> NSColor {
		self[key].color
	}

	/// The stored colour, or `nil` when the user has not chosen one — for the
	/// wells whose "unset" state means "let the appearance decide".
	func storedColor(for key: PreferenceKey<PreferenceColor>) -> NSColor? {
		self[stored: key]?.color
	}
}
