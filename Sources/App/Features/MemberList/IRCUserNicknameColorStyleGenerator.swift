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
import CryptoKit
import os

/// A pinned nickname colour, as it is written to the defaults store: sRGB
/// components a plist editor can read, rather than an `NSKeyedArchiver` blob.
public nonisolated struct NicknameColorComponents: Codable, Equatable, Sendable { // nonisolated: value
	public var red: Double
	public var green: Double
	public var blue: Double
	public var alpha: Double

	/// `nil` for a catalog or pattern colour, which has no components to ask
	/// for without raising an uncatchable exception.
	public init?(_ color: NSColor) {
		guard let color = color.usingColorSpace(.sRGB) else {
			return nil
		}

		red = color.redComponent
		green = color.greenComponent
		blue = color.blueComponent
		alpha = color.alphaComponent
	}

	public init(red: Double, green: Double, blue: Double, alpha: Double) {
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
	public init?(stored value: Any) {
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

	public var storedValue: [String: Double] {
		[
			StoredKey.red: red,
			StoredKey.green: green,
			StoredKey.blue: blue,
			StoredKey.alpha: alpha,
		]
	}

	public var color: NSColor {
		NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
	}
}

public nonisolated enum UserNicknameColorStyleGenerator { // nonisolated: value
	private static let logger = Logger(
		subsystem: Bundle.main.bundleIdentifier ?? "Glasstual",
		category: "NicknameColorStyle"
	)

	/// Native transcript colour for a nickname. Pinned colours still win; an
	/// unpinned name uses the same stable hash as before, with luminance chosen
	/// for the active native theme appearance rather than a CSS style class.
	public static func color(for inputString: String) -> NSColor {
		let normalized = inputString.lowercased()
		if let override = nicknameColorStyleOverride(forKey: normalized) {
			return override
		}

		let hash = hash(for: normalized).uint32Value
		let hue = CGFloat(hash % 360) / 360
		let saturation = CGFloat((hash >> 1) % 26 + 55) / 100
		let isDark = ThemeController.activeSnapshot?.isDarkAppearance ?? false
		let brightness = isDark
			? CGFloat((hash >> 2) % 15 + 75) / 100
			: CGFloat((hash >> 2) % 16 + 35) / 100
		return NSColor(calibratedHue: hue, saturation: saturation, brightness: brightness, alpha: 1)
	}

	/// The theme's colour style does not take part in the hash; the parameter
	/// this used to declare was ignored.
	public static func hash(for inputString: String) -> NSNumber {
		let digest = Insecure.MD5.hash(data: Data("a-\(inputString)".utf8))
		let value = digest.withUnsafeBytes { bytes in
			bytes.loadUnaligned(as: UInt32.self)
		}

		return NSNumber(value: value)
	}

	/// Overrides are stored as their sRGB components. Values written by earlier
	/// builds are `NSKeyedArchiver` blobs and are still read, so a user's pinned
	/// colours survive the format change; the next edit rewrites them.
	public static func nicknameColorStyleOverride(forKey styleKey: String) -> NSColor? {
		guard let stored = storedOverrides()[styleKey] else {
			return nil
		}

		if let dictionary = stored.dictionary,
		   let components = NicknameColorComponents(stored: dictionary.compactMapValues(\.double))
		{
			return components.color
		}

		guard let colorData = stored.data else {
			return nil
		}

		do {
			return try NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: colorData)
		} catch {
			logger.error(
				"Failed to decode archived nickname color for \(styleKey, privacy: .private): \(error.localizedDescription, privacy: .public)"
			)

			return nil
		}
	}

	public static func setNicknameColorStyleOverride(_ styleValue: NSColor?, forKey styleKey: String) {
		let existingOverrides = overridesKey.detachedPropertyListValue?.dictionary

		if existingOverrides == nil, styleValue == nil {
			return
		}

		var overrides = existingOverrides ?? [:]

		if let styleValue {
			guard let components = NicknameColorComponents(styleValue) else {
				logger.error("Could not convert a nickname colour to sRGB for storage")

				return
			}

			overrides[styleKey] = .dictionary(components.storedValue.mapValues(PropertyListValue.double))
		} else {
			overrides.removeValue(forKey: styleKey)
		}

		overridesKey.detachedPropertyListValue = overrides.isEmpty ? nil : .dictionary(overrides)
	}

	/// The overrides as they are stored. Read through the detached handle, not
	/// the main actor's: a nickname colour is resolved while a line renders,
	/// which happens off the main actor.
	private static func storedOverrides() -> [String: PropertyListValue] {
		overridesKey.detachedPropertyListValue?.dictionary ?? [:]
	}

	private static var overridesKey: UntypedPreferenceKey {
		Preferences.Messages.nicknameColorStyleOverrides
	}
}
