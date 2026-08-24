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
import CryptoKit
import os

@objc(IRCUserNicknameColorStyleGenerator)
public final class UserNicknameColorStyleGenerator: NSObject {
	private static let overridesDefaultsKey = "Nickname Color Style Overrides (v2)"
	private static let logger = Logger(
		subsystem: Bundle.main.bundleIdentifier ?? "Glasstual",
		category: "NicknameColorStyle"
	)

	@objc(nicknameColorStyleForString:)
	public static func nicknameColorStyle(for inputString: String) -> String {
		nicknameColorStyle(for: inputString, isOverride: nil)
	}

	@objc(nicknameColorStyleForString:isOverride:)
	public static func nicknameColorStyle(
		for inputString: String,
		isOverride: UnsafeMutablePointer<ObjCBool>?
	) -> String {
		let normalizedString = inputString.lowercased()

		if let override = nicknameColorStyleOverride(forKey: normalizedString) {
			isOverride?.pointee = true

			return override.hexadecimalValue
		}

		isOverride?.pointee = false

		let colorStyle = TXSharedApplication.sharedThemeController().settings.nicknameColorStyle
		let hash = hash(for: normalizedString, colorStyle: colorStyle)

		return nicknameColorStyle(forHash: hash, colorStyle: colorStyle)
	}

	@objc(hashForString:colorStyle:)
	public static func hash(
		for inputString: String,
		colorStyle _: TPCThemeSettingsNicknameColorStyle
	) -> NSNumber {
		let digest = Insecure.MD5.hash(data: Data("a-\(inputString)".utf8))
		let value = digest.withUnsafeBytes { bytes in
			bytes.loadUnaligned(as: UInt32.self)
		}

		return NSNumber(value: value)
	}

	@objc(nicknameColorStyleForHash:colorStyle:)
	public static func nicknameColorStyle(
		forHash stringHash: NSNumber,
		colorStyle: TPCThemeSettingsNicknameColorStyle
	) -> String {
		let hash = stringHash.uint32Value
		let saturationHash = hash >> 1
		let lightnessHash = hash >> 2
		let hue = Int(hash % 360)
		var saturation: Int
		var lightness: Int

		if colorStyle == .light {
			saturation = Int(saturationHash % 50) + 35
			lightness = Int(lightnessHash % 38) + 20

			if hue > 45 && hue <= 195 {
				lightness = Int(lightnessHash % 21) + 20
				saturation =
					lightness > 31
						? Int(saturationHash % 40) + 55
						: Int(saturationHash % 35) + 65
			}

			if hue <= 25 || hue >= 335 {
				saturation = Int(saturationHash % 33) + 45
			}
		} else {
			saturation = Int(saturationHash % 50) + 45
			lightness = Int(lightnessHash % 36) + 45

			if hue >= 280 && hue < 335 {
				lightness = Int(lightnessHash % 36) + 50
			}

			if hue >= 210 && hue < 240 {
				lightness = Int(lightnessHash % 30) + 60
			}

			if hue >= 240 && hue < 280 {
				saturation = Int(saturationHash % 55) + 40
				lightness = Int(lightnessHash % 20) + 65
			}

			if hue <= 25 || hue >= 335 {
				saturation = Int(saturationHash % 33) + 45
			}

			if hue >= 50, hue <= 150 {
				saturation = Int(saturationHash % 50) + 40
			}
		}

		return "hsl(\(hue),\(saturation)%,\(lightness)%)"
	}

	@objc(nicknameColorStyleOverrideForKey:)
	public static func nicknameColorStyleOverride(forKey styleKey: String) -> NSColor? {
		guard
			let overrides = userDefaults.dictionary(forKey: overridesDefaultsKey),
			let colorData = overrides[styleKey] as? Data
		else {
			return nil
		}

		do {
			return try NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: colorData)
		} catch {
			logger.error(
				"Failed to decode nickname color for \(styleKey, privacy: .private): \(error.localizedDescription, privacy: .public)"
			)

			return nil
		}
	}

	@objc(setNicknameColorStyleOverride:forKey:)
	public static func setNicknameColorStyleOverride(_ styleValue: NSColor?, forKey styleKey: String) {
		let existingOverrides = userDefaults.dictionary(forKey: overridesDefaultsKey)

		if existingOverrides == nil, styleValue == nil {
			return
		}

		var overrides = existingOverrides ?? [:]

		if let styleValue {
			do {
				overrides[styleKey] = try NSKeyedArchiver.archivedData(
					withRootObject: styleValue,
					requiringSecureCoding: true
				)
			} catch {
				logger.error(
					"Failed to encode nickname color for \(styleKey, privacy: .private): \(error.localizedDescription, privacy: .public)"
				)

				return
			}
		} else {
			overrides.removeValue(forKey: styleKey)
		}

		if overrides.isEmpty {
			userDefaults.removeObject(forKey: overridesDefaultsKey)
		} else {
			userDefaults.set(overrides, forKey: overridesDefaultsKey)
		}
	}

	private static var userDefaults: TPCPreferencesUserDefaults {
		TPCPreferencesUserDefaults.shared()
	}
}
