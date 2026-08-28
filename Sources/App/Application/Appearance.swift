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

/// An immutable snapshot of the appearance the application is currently
/// drawing in. It is built once per appearance change and only ever read
/// afterwards, so it is a value.
public struct AppearancePropertyCollection: TXAppearanceProperties, Equatable, Sendable {
	public var appearanceName = ""
	public var appearanceType: TXAppearanceType = .light
	public var isDarkAppearance = false
	public var appKitAppearanceTarget: TXAppKitAppearanceTarget = .none

	public var appKitAppearance: NSAppearance? {
		if appKitAppearanceTarget == .none {
			return nil
		}

		if isDarkAppearance {
			return Self.appKitDarkAppearance()
		}

		return Self.appKitLightAppearance()
	}

	public var shortAppearanceDescription: String {
		isDarkAppearance ? "dark" : "light"
	}

	@MainActor public static func systemWideDarkModeEnabled() -> Bool {
		NSApp.effectiveAppearance.bestMatch(from: [NSAppearance.Name.darkAqua]) != nil
	}

	public static func appKitDarkAppearance() -> NSAppearance? {
		NSAppearance(named: .darkAqua)
	}

	public static func appKitLightAppearance() -> NSAppearance? {
		NSAppearance(named: .aqua)
	}
}

@objc(TXAppearance)
@MainActor
public final class Appearance: NSObject {
	public private(set) var properties = AppearancePropertyCollection()

	/// `properties` starts at its default value, so "has the appearance ever
	/// been resolved" needs its own flag rather than a nil check.
	private var hasResolvedAppearance = false
	private var isApplyingAppearance = false
	private var effectiveAppearanceObservation: NSKeyValueObservation?

	override public init() {
		super.init()
		prepareInitialState()
	}

	/** Isolated so the teardown below runs on the main actor no matter which thread
	 drops the last reference. */
	isolated deinit {
		removeObservers()
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
			/* ISOLATION-EXCEPTION: `NSKeyValueObservation`'s change handler is
			 declared nonisolated. AppKit posts `effectiveAppearance` changes on the
			 main thread, which is what makes the assumption hold. */
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

	/** Two independent registrations, so they get torn down independently: an
	 already-invalidated KVO token used to skip the workspace observer too. */
	private func removeObservers() {
		NSWorkspace.shared.notificationCenter.removeObserver(self)

		effectiveAppearanceObservation?.invalidate()
		effectiveAppearanceObservation = nil
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
			hasResolvedAppearance == false
				|| oldProperties.appearanceType != appearanceType
				|| oldProperties.appKitAppearanceTarget != appKitAppearanceTarget

		var systemChanged = systemChanged

		if changeAppearance == false {
			if systemChanged == false {
				return
			}
		} else {
			systemChanged = false
		}

		properties = AppearancePropertyCollection(
			appearanceName: appearanceDefaultName,
			appearanceType: appearanceType,
			isDarkAppearance: isAppearanceDark,
			appKitAppearanceTarget: appKitAppearanceTarget
		)
		hasResolvedAppearance = true

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
