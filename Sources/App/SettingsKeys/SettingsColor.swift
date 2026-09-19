// Copyright (c) 2010 - 2018 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
import CocoaExtensions
import os

private nonisolated let settingsColorLogger = Logger(
	subsystem: LogSubsystem.current,
	category: "SettingsColor"
)

/** A colour setting with a versioned Codable representation.

 Holding the components rather than archived bytes keeps the declared default
 comparable after decoding: two archives of the same colour need not contain
 identical bytes. */
nonisolated struct SettingsColor: SettingValue, Codable {
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

	static func settingValue(from object: Any) -> SettingsColor? {
		guard let data = object as? Data,
		      let payload = try? PropertyListDecoder().decode(StoredColor.self, from: data),
		      payload.version == StoredColor.currentVersion,
		      [payload.color.red, payload.color.green, payload.color.blue, payload.color.alpha]
		      .allSatisfy(\.isFinite)
		else {
			return nil
		}

		return payload.color
	}

	var settingObject: Any? {
		do {
			guard [red, green, blue, alpha].allSatisfy(\.isFinite) else { return nil }
			return try PropertyListEncoder().encode(StoredColor(color: self))
		} catch {
			/* Nothing is written for a colour that will not archive. The empty
			 `Data` this used to store read back as unarchivable, so the choice
			 was lost and the store held a blob that shadowed nothing. */
			settingsColorLogger.error(
				"Could not archive a colour setting: \(error.localizedDescription, privacy: .public)"
			)

			return nil
		}
	}

	private struct StoredColor: Codable {
		static let currentVersion = 1
		var version = currentVersion
		let color: SettingsColor
	}
}

nonisolated extension GlasstualUserDefaults { // nonisolated: guarded
	/// The stored colour, or the key's declared default when nothing is stored.
	func color(for key: SettingsKey<SettingsColor>) -> NSColor {
		self[key].color
	}

	/// The stored colour, or `nil` when the user has not chosen one — for the
	/// wells whose "unset" state means "let the appearance decide".
	func storedColor(for key: SettingsKey<SettingsColor>) -> NSColor? {
		self[stored: key]?.color
	}
}
