/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2018 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 *********************************************************************** */

import AppKit
import CocoaExtensions
import os

/// A colour as spelled in the appearance property lists: `{ type = 1|2|3;
/// value = "…"; }`. The `type` picks how `value` is read.
public enum AppearanceColor: Decodable, Equatable, Sendable {
	/// `type = 1` — one or two whitespace-separated components: white, alpha.
	case calibratedWhite(white: Double, alpha: Double)
	/// `type = 2` — three or four whitespace-separated components: r, g, b, alpha.
	case calibratedRGB(red: Double, green: Double, blue: Double, alpha: Double)
	/// `type = 3` — the name of a semantic `NSColor` class property.
	case system(name: String)

	private enum CodingKeys: String, CodingKey {
		case type
		case value
	}

	private enum Kind: UInt, Decodable {
		case calibratedWhite = 1
		case rgb = 2
		case system = 3
	}

	public init(from decoder: any Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)
		let kind = try container.decode(Kind.self, forKey: .type)
		let value = try container.decode(String.self, forKey: .value)

		switch kind {
		case .calibratedWhite:
			let components = Self.components(of: value) ?? []
			guard let white = components.first else {
				throw DecodingError.dataCorruptedError(
					forKey: .value,
					in: container,
					debugDescription: "A calibrated-white colour needs at least one component"
				)
			}
			self = .calibratedWhite(white: white, alpha: components.count > 1 ? components[1] : 1)

		case .rgb:
			let components = Self.components(of: value) ?? []
			guard components.count >= 3 else {
				throw DecodingError.dataCorruptedError(
					forKey: .value,
					in: container,
					debugDescription: "An RGB colour needs at least three components"
				)
			}
			self = .calibratedRGB(
				red: components[0],
				green: components[1],
				blue: components[2],
				alpha: components.count > 3 ? components[3] : 1
			)

		case .system:
			self = .system(name: value)
		}
	}

	/// `nil` only for a `system` colour naming something AppKit does not have;
	/// that used to be an `NSSelectorFromString` + `perform` away from calling
	/// an arbitrary zero-argument method on `NSColor`.
	public var color: NSColor? {
		switch self {
		case let .calibratedWhite(white, alpha):
			NSColor(calibratedWhite: white, alpha: alpha)
		case let .calibratedRGB(red, green, blue, alpha):
			NSColor.textual_calibratedColor(red: red, green: green, blue: blue, alpha: alpha)
		case let .system(name):
			Self.systemColors[name]
		}
	}

	/// The semantic colours the shipped appearance plists are allowed to name.
	/// A table rather than a runtime lookup, so an unknown name is a missing
	/// entry here instead of a selector sent to `NSColor`.
	public static let systemColors: [String: NSColor] = [
		"alternateSelectedControlTextColor": .alternateSelectedControlTextColor,
		"controlAccentColor": .controlAccentColor,
		"controlBackgroundColor": .controlBackgroundColor,
		"controlColor": .controlColor,
		"controlTextColor": .controlTextColor,
		"disabledControlTextColor": .disabledControlTextColor,
		"gridColor": .gridColor,
		"headerTextColor": .headerTextColor,
		"labelColor": .labelColor,
		"linkColor": .linkColor,
		"placeholderTextColor": .placeholderTextColor,
		"quaternaryLabelColor": .quaternaryLabelColor,
		"secondaryLabelColor": .secondaryLabelColor,
		"selectedContentBackgroundColor": .selectedContentBackgroundColor,
		"selectedControlColor": .selectedControlColor,
		"selectedControlTextColor": .selectedControlTextColor,
		"selectedMenuItemTextColor": .selectedMenuItemTextColor,
		"selectedTextBackgroundColor": .selectedTextBackgroundColor,
		"selectedTextColor": .selectedTextColor,
		"separatorColor": .separatorColor,
		"shadowColor": .shadowColor,
		"tertiaryLabelColor": .tertiaryLabelColor,
		"textBackgroundColor": .textBackgroundColor,
		"textColor": .textColor,
		"underPageBackgroundColor": .underPageBackgroundColor,
		"unemphasizedSelectedContentBackgroundColor": .unemphasizedSelectedContentBackgroundColor,
		"unemphasizedSelectedTextBackgroundColor": .unemphasizedSelectedTextBackgroundColor,
		"unemphasizedSelectedTextColor": .unemphasizedSelectedTextColor,
		"windowBackgroundColor": .windowBackgroundColor,
		"windowFrameTextColor": .windowFrameTextColor,
	]

	/// `nil` when any token is not a number, so a typo in a plist fails the
	/// decode instead of silently becoming a zero component.
	private static func components(of value: String) -> [Double]? {
		let tokens = value.split(whereSeparator: \.isWhitespace)
		let numbers = tokens.compactMap { Double($0) }
		return numbers.count == tokens.count ? numbers : nil
	}
}

/// A colour that may differ between an active and an inactive window. A plist
/// entry either states one colour or the `activeWindow`/`inactiveWindow` pair.
public enum AppearanceStatefulColor: Decodable, Equatable, Sendable {
	case constant(AppearanceColor)
	case stateful(active: AppearanceColor, inactive: AppearanceColor)

	private enum CodingKeys: String, CodingKey {
		case activeWindow
		case inactiveWindow
	}

	public init(from decoder: any Decoder) throws {
		if let container = try? decoder.container(keyedBy: CodingKeys.self),
		   container.contains(.activeWindow) || container.contains(.inactiveWindow)
		{
			let active = try container.decode(AppearanceColor.self, forKey: .activeWindow)
			let inactive = try container.decode(AppearanceColor.self, forKey: .inactiveWindow)
			self = .stateful(active: active, inactive: inactive)
			return
		}

		self = try .constant(AppearanceColor(from: decoder))
	}

	public func color(forActiveWindow isActive: Bool) -> NSColor? {
		switch self {
		case let .constant(color):
			color.color
		case let .stateful(active, inactive):
			isActive ? active.color : inactive.color
		}
	}
}

/// `{ width = …; height = …; }` as it appears in the appearance plists.
public struct AppearanceSize: Decodable, Equatable, Sendable {
	public let width: Double
	public let height: Double

	public var size: NSSize {
		NSSize(width: width, height: height)
	}
}

/// Reads one appearance property list. The file is a dictionary of appearance
/// name (`Tahoe`) to that appearance's schema, so the loader picks the entry
/// matching the application's current appearance.
public enum AppearanceSchema {
	private static let logger = Logger(
		subsystem: Bundle.main.bundleIdentifier ?? "Glasstual",
		category: "AppearanceSchema"
	)

	/// Decodes `resource`.plist from the main bundle, returning the schema for
	/// `appearanceName`, or `nil` when the resource, the appearance entry or the
	/// schema itself does not decode.
	public static func load<Schema: Decodable>(
		_: Schema.Type = Schema.self,
		resource: String,
		appearanceName: String
	) -> Schema? {
		guard let url = Bundle.main.url(forResource: resource, withExtension: "plist") else {
			logger.error("Missing appearance resource: \(resource, privacy: .public)")
			return nil
		}

		return load(resource: url, appearanceName: appearanceName)
	}

	public static func load<Schema: Decodable>(
		_: Schema.Type = Schema.self,
		resource url: URL,
		appearanceName: String
	) -> Schema? {
		do {
			let data = try Data(contentsOf: url)
			let appearances = try PropertyListDecoder().decode([String: Schema].self, from: data)

			guard let schema = appearances[appearanceName] else {
				logger.error("Missing appearance '\(appearanceName, privacy: .public)' in \(url.lastPathComponent)")
				return nil
			}

			return schema
		} catch {
			logger.error("Unreadable appearance \(url.lastPathComponent): \(error, privacy: .public)")
			return nil
		}
	}
}

/// Base class for the three appearance objects loaded from a property list.
/// It carries the application-wide appearance snapshot the subclasses need to
/// pick their entry out of the file.
open class ApplicationAppearance: TXAppearanceProperties {
	private let applicationProperties: AppearancePropertyCollection

	public init(applicationProperties: AppearancePropertyCollection) {
		self.applicationProperties = applicationProperties
	}

	/// The appearance snapshot the application is drawing in right now.
	@MainActor
	public static var currentApplicationProperties: AppearancePropertyCollection {
		SharedApplication.sharedAppearance().properties
	}

	public var appearanceName: String {
		applicationProperties.appearanceName
	}

	public var appearanceType: TXAppearanceType {
		applicationProperties.appearanceType
	}

	public var shortAppearanceDescription: String {
		applicationProperties.shortAppearanceDescription
	}

	public var isDarkAppearance: Bool {
		applicationProperties.isDarkAppearance
	}

	public var appKitAppearanceTarget: TXAppKitAppearanceTarget {
		applicationProperties.appKitAppearanceTarget
	}

	public var appKitAppearance: NSAppearance? {
		applicationProperties.appKitAppearance
	}
}
