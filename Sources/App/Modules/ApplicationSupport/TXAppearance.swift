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

private enum AppearanceKVOContext {
	nonisolated(unsafe) static var token = 0
}

private let appearanceDefaultName = "Tahoe"

private let appearanceTerminationLogger = Logger(
	subsystem: Bundle.main.bundleIdentifier ?? "Glasstual",
	category: "Termination"
)

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

	@objc public class func systemWideDarkModeEnabled() -> Bool {
		NSApp.effectiveAppearance.bestMatch(from: [NSAppearance.Name.darkAqua]) != nil
	}

	@objc public class func appKitDarkAppearance() -> NSAppearance? {
		NSAppearance(named: .darkAqua)
	}

	@objc public class func appKitLightAppearance() -> NSAppearance? {
		NSAppearance(named: .aqua)
	}
}

@objc(TXAppearance)
@MainActor
public final class Appearance: NSObject {
	@objc public private(set) var properties: AppearancePropertyCollection!

	private var isApplyingAppearance = false
	private var isObservingAppearance = false

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

		NSApp.addObserver(self, forKeyPath: "effectiveAppearance", options: .new, context: &AppearanceKVOContext.token)
		isObservingAppearance = true
	}

	@objc public func prepareForApplicationTermination() {
		appearanceTerminationLogger.debug("Removing appearance change observers")
		removeObservers()
	}

	private func removeObservers() {
		guard isObservingAppearance else {
			return
		}

		isObservingAppearance = false
		NSWorkspace.shared.notificationCenter.removeObserver(self)
		NSApp.removeObserver(self, forKeyPath: "effectiveAppearance", context: &AppearanceKVOContext.token)
	}

	override public func observeValue(
		forKeyPath keyPath: String?,
		of object: Any?,
		change: [NSKeyValueChangeKey: Any]?,
		context: UnsafeMutableRawPointer?
	) {
		guard context == &AppearanceKVOContext.token else {
			super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context)
			return
		}

		if isApplyingAppearance {
			return
		}

		if keyPath == "effectiveAppearance" {
			applicationAppearanceChanged()
		}
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
		let preferredAppearance = TPCPreferences.appearance()

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
			name: NSNotification.Name("TXApplicationAppearanceChangedNotification"),
			object: self
		)
	}

	private func notifySystemAppearanceChanged() {
		NotificationCenter.default.post(
			name: NSNotification.Name("TXSystemAppearanceChangedNotification"),
			object: self
		)
	}
}
