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

private let appearanceDefaultName = "Tahoe"

private let appearanceTerminationLogger = Logger(
	subsystem: Bundle.main.bundleIdentifier ?? "Glasstual",
	category: "Termination"
)

public extension Notification.Name {
	static let applicationAppearanceChanged = Notification.Name("TXApplicationAppearanceChangedNotification")
	static let systemAppearanceChanged = Notification.Name("TXSystemAppearanceChangedNotification")
}

@objc(TXAppearancePropertyCollection)
public final class AppearancePropertyCollection: NSObject, TXAppearanceProperties {
	@objc public var appearanceName = ""
	@objc public var appearanceType: TXAppearanceType = .light
	@objc public var isDarkAppearance = false
	@objc public var appKitAppearanceTarget: TXAppKitAppearanceTarget = .none

	@objc public var appKitAppearance: NSAppearance? {
		if appKitAppearanceTarget == .none {
			return nil
		}

		if isDarkAppearance {
			return Self.appKitDarkAppearance()
		}

		return Self.appKitLightAppearance()
	}

	@objc public var shortAppearanceDescription: String {
		isDarkAppearance ? "dark" : "light"
	}

	@MainActor @objc public static func systemWideDarkModeEnabled() -> Bool {
		NSApp.effectiveAppearance.bestMatch(from: [NSAppearance.Name.darkAqua]) != nil
	}

	@objc public static func appKitDarkAppearance() -> NSAppearance? {
		NSAppearance(named: .darkAqua)
	}

	@objc public static func appKitLightAppearance() -> NSAppearance? {
		NSAppearance(named: .aqua)
	}
}

@objc(TXAppearance)
@MainActor
public final class Appearance: NSObject {
	@objc public private(set) var properties: AppearancePropertyCollection!

	private var isApplyingAppearance = false
	private var effectiveAppearanceObservation: NSKeyValueObservation?

	override public init() {
		super.init()
		prepareInitialState()
	}

	deinit {
		MainActor.assumeIsolated {
			removeObservers()
		}
	}

	private func prepareInitialState() {
		updateAppearance()

		NSWorkspace.shared.notificationCenter.addObserver(
			self,
			selector: #selector(accessibilityDisplayOptionsDidChange(_:)),
			name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
			object: nil
		)

		effectiveAppearanceObservation = NSApp.observe(\.effectiveAppearance, options: .new) { [weak self] _, _ in
			MainActor.assumeIsolated {
				guard let self, self.isApplyingAppearance == false else {
					return
				}
				self.applicationAppearanceChanged()
			}
		}
	}

	@objc public func prepareForApplicationTermination() {
		appearanceTerminationLogger.debug("Removing appearance change observers")
		removeObservers()
	}

	private func removeObservers() {
		guard let effectiveAppearanceObservation else {
			return
		}

		self.effectiveAppearanceObservation = nil
		NSWorkspace.shared.notificationCenter.removeObserver(self)
		effectiveAppearanceObservation.invalidate()
	}

	private func applicationAppearanceChanged() {
		Task { @MainActor [weak self] in
			self?.updateAppearanceBySystemChange(true)
		}
	}

	@objc private func accessibilityDisplayOptionsDidChange(_: Notification) {
		updateAppearanceBySystemChange(true)
	}

	@objc public func updateAppearance() {
		updateAppearanceBySystemChange(false)
	}

	private func updateAppearanceBySystemChange(_ systemChanged: Bool) {
		var appearanceType: TXAppearanceType = .light
		let preferredAppearance = TextualPreferences.appearance()

		switch preferredAppearance {
		case .inherited:
			applyAppKitAppearance(nil)

			if AppearancePropertyCollection.systemWideDarkModeEnabled() {
				appearanceType = .dark
			}
		case .dark:
			appearanceType = .dark
		default:
			break
		}

		let isAppearanceDark = appearanceType == .dark

		var appKitAppearanceTarget: TXAppKitAppearanceTarget = .none
		if preferredAppearance != .inherited {
			appKitAppearanceTarget = .window
		}

		let oldProperties = properties
		let changeAppearance =
			oldProperties == nil
				|| oldProperties!.appearanceType != appearanceType
				|| oldProperties!.appKitAppearanceTarget != appKitAppearanceTarget

		var systemChanged = systemChanged

		if changeAppearance == false {
			if systemChanged == false {
				return
			}
		} else {
			systemChanged = false
		}

		let newProperties = AppearancePropertyCollection()
		newProperties.appearanceName = appearanceDefaultName
		newProperties.appearanceType = appearanceType
		newProperties.isDarkAppearance = isAppearanceDark
		newProperties.appKitAppearanceTarget = appKitAppearanceTarget
		properties = newProperties

		if preferredAppearance == .inherited {
			applyAppKitAppearance(nil)
		} else if isAppearanceDark {
			applyAppKitAppearance(AppearancePropertyCollection.appKitDarkAppearance())
		} else {
			applyAppKitAppearance(AppearancePropertyCollection.appKitLightAppearance())
		}

		if systemChanged {
			notifySystemAppearanceChanged()
		} else {
			notifyApplicationAppearanceChanged()
		}
	}

	private func applyAppKitAppearance(_ appearance: NSAppearance?) {
		let current = NSApp.appearance

		if current === appearance {
			return
		}

		if let current, let appearance, current.name == appearance.name {
			return
		}

		isApplyingAppearance = true
		NSApp.appearance = appearance
		isApplyingAppearance = false
	}

	private func notifyApplicationAppearanceChanged() {
		NotificationCenter.default.post(
			name: .applicationAppearanceChanged,
			object: self
		)
	}

	private func notifySystemAppearanceChanged() {
		NotificationCenter.default.post(
			name: .systemAppearanceChanged,
			object: self
		)
	}
}
