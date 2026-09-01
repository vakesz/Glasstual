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
import Combine
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

@MainActor
public final class Appearance: NSObject {
	public private(set) var properties = AppearancePropertyCollection()

	/// `properties` starts at its default value, so "has the appearance ever
	/// been resolved" needs its own flag rather than a nil check.
	private var hasResolvedAppearance = false

	/// The effective appearance this object's last write to `NSApp` produced.
	///
	/// The observation below is delivered on a later main-actor turn, so a
	/// "currently applying" flag would already have been cleared by the time the
	/// change arrives. The resulting name is what identifies it as our own.
	private var selfAppliedAppearanceName: NSAppearance.Name?
	private var effectiveAppearanceObservation: Task<Void, Never>?
	/// The workspace's accessibility-options notification.
	private let notifications = NotificationSubscriptions()

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

		notifications.observe(
			NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
			center: NSWorkspace.shared.notificationCenter
		) { [weak self] notification in
			self?.accessibilityDisplayOptionsDidChange(notification)
		}

		/* `observe`'s change handler is nonisolated; awaiting the key path's
		 values reads this object's state where it lives. */
		effectiveAppearanceObservation = Task { @MainActor [weak self] in
			for await appearance in NSApp.publisher(for: \.effectiveAppearance, options: .new).bufferedValues {
				guard let self else {
					return
				}

				/* The change this object caused itself is not news, and
				 answering it would post a system-appearance change nothing
				 asked for. */
				if selfAppliedAppearanceName == appearance.name {
					selfAppliedAppearanceName = nil
					continue
				}

				applicationAppearanceChanged()
			}
		}
	}

	public func prepareForApplicationTermination() {
		appearanceTerminationLogger.debug("Removing appearance change observers")
		removeObservers()
	}

	/** Two independent registrations, so they get torn down independently: an
	 already-invalidated KVO token used to skip the workspace observer too. */
	private func removeObservers() {
		notifications.cancelAll()

		effectiveAppearanceObservation?.cancel()
		effectiveAppearanceObservation = nil
	}

	private func applicationAppearanceChanged() {
		updateAppearanceBySystemChange(true)
	}

	private func accessibilityDisplayOptionsDidChange(_: Notification) {
		updateAppearanceBySystemChange(true)
	}

	public func updateAppearance() {
		updateAppearanceBySystemChange(false)
	}

	private func updateAppearanceBySystemChange(_ systemChanged: Bool) {
		var appearanceType: TXAppearanceType = .light
		let preferredAppearance = Preferences.Appearance.preferredAppearance.value

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

		let previousEffectiveName = NSApp.effectiveAppearance.name
		NSApp.appearance = appearance
		let newEffectiveName = NSApp.effectiveAppearance.name

		/* Only remember it when the write actually moved the effective
		 appearance; otherwise there is no observation to discount and the name
		 would swallow the next genuine change to it. */
		selfAppliedAppearanceName = newEffectiveName == previousEffectiveName ? nil : newEffectiveName
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
