/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \\ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\\___/_/\\_\\__|\\__,_|\\__,_|_|
 *
 * Copyright (c) 2018 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 *********************************************************************** */

import AppKit
import os

private enum ListAppearanceColorType: UInt {
	case calibratedWhite = 1
	case rgb = 2
	case system = 3
}

@objc(TVCAppearance)
open class ViewAppearance: NSObject {
	private static let logger = Logger(
		subsystem: Bundle.main.bundleIdentifier ?? "Glasstual",
		category: "ViewAppearance"
	)

	@objc public private(set) var appearanceProperties: [String: Any]?

	@available(*, unavailable)
	override public init() {
		fatalError("init() is unavailable; use init(appearanceNamed:at:)")
	}

	@objc(initWithAppearanceNamed:atURL:)
	public init?(appearanceNamed appearanceName: String, at appearanceLocation: URL) {
		super.init()

		guard loadAppearanceNamed(appearanceName, at: appearanceLocation) else {
			return nil
		}
	}

	private func loadAppearanceNamed(_ appearanceName: String, at appearanceLocation: URL) -> Bool {
		guard let appearances = NSDictionary(contentsOf: appearanceLocation) as? [String: Any],
		      let appearance = appearances[appearanceName] as? [String: Any]
		else {
			return false
		}

		appearanceProperties = appearance
		return true
	}

	@objc
	open func flushAppearanceProperties() {
		appearanceProperties = nil
	}

	// MARK: - Utilities

	private func value(inGroup group: [String: Any], withKey key: String, expectedType: AnyClass) -> Any? {
		guard let referenceObject = group[key],
		      (referenceObject as AnyObject).isKind(of: expectedType)
		else {
			return nil
		}

		return referenceObject
	}

	private func statefulValue(
		_ referenceObject: [String: Any],
		forActiveWindow: Bool,
		expectedType: AnyClass
	) -> Any? {
		let stateKey = forActiveWindow ? "activeWindow" : "inactiveWindow"

		guard let stateValue = referenceObject[stateKey],
		      (stateValue as AnyObject).isKind(of: expectedType)
		else {
			return nil
		}

		return stateValue
	}

	private func statefulDictionary(
		_ referenceObject: [String: Any],
		forActiveWindow: Bool
	) -> [String: Any]? {
		if referenceObject["activeWindow"] == nil, referenceObject["inactiveWindow"] == nil {
			return referenceObject
		}

		return statefulValue(referenceObject, forActiveWindow: forActiveWindow, expectedType: NSDictionary.self)
			as? [String: Any]
	}

	// MARK: - Color

	@objc(colorForKey:)
	open func color(forKey key: String) -> NSColor? {
		guard let group = appearanceProperties else {
			return nil
		}

		return color(inGroup: group, withKey: key)
	}

	@objc(colorInGroup:withKey:)
	open func color(inGroup group: [String: Any], withKey key: String) -> NSColor? {
		guard let colorProperties = value(inGroup: group, withKey: key, expectedType: NSDictionary.self)
			as? [String: Any]
		else {
			return nil
		}

		return color(withProperties: colorProperties)
	}

	@objc(colorForKey:forActiveWindow:)
	open func color(forKey key: String, forActiveWindow: Bool) -> NSColor? {
		guard let group = appearanceProperties else {
			return nil
		}

		return color(inGroup: group, withKey: key, forActiveWindow: forActiveWindow)
	}

	@objc(colorInGroup:withKey:forActiveWindow:)
	open func color(inGroup group: [String: Any], withKey key: String, forActiveWindow: Bool) -> NSColor? {
		guard let referenceObject = value(inGroup: group, withKey: key, expectedType: NSDictionary.self)
			as? [String: Any]
		else {
			return nil
		}

		guard let colorProperties = statefulDictionary(referenceObject, forActiveWindow: forActiveWindow) else {
			return nil
		}

		return color(withProperties: colorProperties)
	}

	private func color(withProperties colorProperties: [String: Any]) -> NSColor? {
		guard let colorValue = colorProperties["value"] as? String else {
			return nil
		}

		let colorTypeRaw = (colorProperties["type"] as? NSNumber)?.uintValue ?? 0
		let colorType = ListAppearanceColorType(rawValue: colorTypeRaw)

		switch colorType {
		case .calibratedWhite:
			let components = colorValue.components(separatedBy: .whitespaces)

			guard components.isEmpty == false else {
				return nil
			}

			let white = Self.double(from: components, at: 0)
			var alpha = 1.0

			if components.count == 2 {
				alpha = Self.double(from: components, at: 1)
			}

			return NSColor(calibratedWhite: white, alpha: alpha)

		case .rgb:
			let components = colorValue.components(separatedBy: .whitespaces)

			guard components.count >= 3 else {
				return nil
			}

			let red = Self.double(from: components, at: 0)
			let green = Self.double(from: components, at: 1)
			let blue = Self.double(from: components, at: 2)
			var alpha = 1.0

			if components.count == 4 {
				alpha = Self.double(from: components, at: 3)
			}

			return NSColor.calibratedColor(withRed: red, green: green, blue: blue, alpha: alpha)

		case .system:
			let selector = NSSelectorFromString(colorValue)

			guard NSColor.responds(to: selector) else {
				Self.logger.error("Missing color: \(colorValue, privacy: .public)")
				return nil
			}

			return NSColor.perform(selector)?.takeUnretainedValue() as? NSColor

		case nil:
			return nil
		}
	}

	private static func double(from components: [String], at index: Int) -> Double {
		Double(components[index]) ?? 0
	}

	// MARK: - Size

	@objc(sizeForKey:)
	open func size(forKey key: String) -> NSSize {
		guard let group = appearanceProperties else {
			return .zero
		}

		return size(inGroup: group, withKey: key)
	}

	@objc(sizeInGroup:withKey:)
	open func size(inGroup group: [String: Any], withKey key: String) -> NSSize {
		guard let referenceObject = value(inGroup: group, withKey: key, expectedType: NSDictionary.self)
			as? [String: Any]
		else {
			return .zero
		}

		let width = (referenceObject["width"] as? NSNumber)?.doubleValue ?? 0
		let height = (referenceObject["height"] as? NSNumber)?.doubleValue ?? 0

		return NSSize(width: width, height: height)
	}

	// MARK: - Measurement

	@objc(measurementForKey:)
	open func measurement(forKey key: String) -> CGFloat {
		guard let group = appearanceProperties else {
			return 0
		}

		return measurement(inGroup: group, withKey: key)
	}

	@objc(measurementInGroup:withKey:)
	open func measurement(inGroup group: [String: Any], withKey key: String) -> CGFloat {
		guard let referenceObject = value(inGroup: group, withKey: key, expectedType: NSNumber.self) as? NSNumber
		else {
			return 0
		}

		return CGFloat(referenceObject.doubleValue)
	}
}

@objc(TVCApplicationAppearance)
open class ApplicationAppearance: ViewAppearance, TXAppearanceProperties {
	private let applicationProperties: AppearancePropertyCollection

	@objc(initWithAppearanceNamed:atURL:)
	override public init?(appearanceNamed _: String, at _: URL) {
		assertionFailure("Use -initWithAppearanceAtURL: instead")
		return nil
	}

	@objc(initWithAppearanceAtURL:)
	public init?(appearanceAt appearanceLocation: URL) {
		nonisolated(unsafe) var capturedProperties: AppearancePropertyCollection?

		if Thread.isMainThread {
			MainActor.assumeIsolated {
				capturedProperties = SharedApplication.sharedAppearance().properties
			}
		} else {
			DispatchQueue.main.sync {
				MainActor.assumeIsolated {
					capturedProperties = SharedApplication.sharedAppearance().properties
				}
			}
		}

		guard let applicationProperties = capturedProperties else {
			return nil
		}

		self.applicationProperties = applicationProperties

		super.init(appearanceNamed: applicationProperties.appearanceName, at: appearanceLocation)
	}

	@objc public var appearanceName: String {
		applicationProperties.appearanceName
	}

	@objc public var appearanceType: TXAppearanceType {
		applicationProperties.appearanceType
	}

	@objc public var shortAppearanceDescription: String {
		applicationProperties.shortAppearanceDescription
	}

	@objc public var isDarkAppearance: Bool {
		applicationProperties.isDarkAppearance
	}

	@objc public var appKitAppearanceTarget: TXAppKitAppearanceTarget {
		applicationProperties.appKitAppearanceTarget
	}

	@objc public var appKitAppearance: NSAppearance? {
		applicationProperties.appKitAppearance
	}
}
