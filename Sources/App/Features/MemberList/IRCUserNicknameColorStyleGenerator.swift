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

/** The pinned nickname colours, read once.

 Resolving one colour reads the overrides dictionary out of the defaults store,
 and every detached read builds its own handle on the suite: a transcript batch
 that colours a hundred nicknames paid for a hundred handles. The table cannot
 change part-way through a batch, so it is a value a caller reads once and hands
 to every name it has to colour. */
public nonisolated struct NicknameColorOverrides: Sendable { // nonisolated: value
	fileprivate let stored: [String: PropertyListValue]
}

public nonisolated enum UserNicknameColorStyleGenerator { // nonisolated: value
	private static let logger = Logger(
		subsystem: Bundle.main.bundleIdentifier ?? "Glasstual",
		category: "NicknameColorStyle"
	)

	/// Native transcript colour for a nickname. Pinned colours still win; an
	/// unpinned name uses the same stable hash as before, drawn for the active
	/// native theme appearance.
	public static func color(for inputString: String, overrides: NicknameColorOverrides? = nil) -> NSColor {
		color(
			for: inputString,
			isDark: ThemeSnapshotStore.current.isDarkAppearance,
			overrides: overrides
		)
	}

	/// The pinned colours as they stand, for a caller about to resolve more than
	/// one nickname.
	public static func overridesSnapshot() -> NicknameColorOverrides {
		NicknameColorOverrides(stored: storedOverrides())
	}

	/// The chroma every generated nickname colour is drawn at, shared with
	/// whoever needs the same hue at a lightness of their own.
	public static let chroma = 0.13

	/** The colour for one appearance.

	 The hue comes from the hash. Chroma is fixed, and lightness is fixed per
	 appearance, both in the OKLCH space, so every hue reads at the same
	 perceived brightness: a blue is as legible as a yellow on a dark ground,
	 and neither washes out on a light one. HSB brightness could not promise
	 that, and pure blues at 75 % brightness vanished against a dark transcript. */
	public static func color(
		for inputString: String,
		isDark: Bool,
		overrides: NicknameColorOverrides? = nil
	) -> NSColor {
		let normalized = inputString.lowercased()
		if let override = nicknameColorStyleOverride(forKey: normalized, in: overrides) {
			return override
		}

		return OKLCHColor(lightness: isDark ? 0.80 : 0.50, chroma: chroma, hue: hue(for: inputString)).nsColor
	}

	/// The hue in degrees a nickname hashes to. A caller that draws the name on
	/// a ground of its own — an avatar, a chip — keeps the identity the reader
	/// learned from the transcript while choosing its own lightness.
	public static func hue(for inputString: String) -> Double {
		Double(hash(for: inputString.lowercased()).uint32Value % 360)
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
	public static func nicknameColorStyleOverride(
		forKey styleKey: String,
		in overrides: NicknameColorOverrides? = nil
	) -> NSColor? {
		guard let stored = (overrides?.stored ?? storedOverrides())[styleKey] else {
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
