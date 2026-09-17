// Copyright (c) 2018 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
import Combine
import os

private let appearanceTerminationLogger = Logger(
	subsystem: Bundle.main.bundleIdentifier ?? "Glasstual",
	category: "Termination"
)

extension Notification.Name {
	static let applicationAppearanceChanged = Notification.Name("Glasstual.applicationAppearanceChanged")
	static let systemAppearanceChanged = Notification.Name("Glasstual.systemAppearanceChanged")
}

/// Which of the two appearances the application draws in.
enum AppearanceType: UInt, Sendable {
	case light
	case dark
}

/// An immutable snapshot of the appearance the application is currently
/// drawing in. It is built once per appearance change and only ever read
/// afterwards, so it is a value.
struct AppearancePropertyCollection: Equatable, Sendable {
	var appearanceType: AppearanceType = .light
	var isDarkAppearance = false
	/// Whether the appearance is the application's own choice rather than the
	/// system's. Only then does a window carry an `NSAppearance`.
	var overridesAppKitAppearance = false

	var appKitAppearance: NSAppearance? {
		guard overridesAppKitAppearance else {
			return nil
		}

		return isDarkAppearance ? Self.appKitDarkAppearance() : Self.appKitLightAppearance()
	}

	@MainActor static func systemWideDarkModeEnabled() -> Bool {
		NSApp.effectiveAppearance.bestMatch(from: [NSAppearance.Name.darkAqua]) != nil
	}

	static func appKitDarkAppearance() -> NSAppearance? {
		NSAppearance(named: .darkAqua)
	}

	static func appKitLightAppearance() -> NSAppearance? {
		NSAppearance(named: .aqua)
	}
}

@MainActor
final class Appearance: NSObject {
	private(set) var properties = AppearancePropertyCollection()

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

	override init() {
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

	func prepareForApplicationTermination() {
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

	func updateAppearance() {
		updateAppearanceBySystemChange(false)
	}

	private func updateAppearanceBySystemChange(_ systemChanged: Bool) {
		var appearanceType: AppearanceType = .light
		let preferredAppearance = Preferences.Appearance.preferredAppearance.value

		switch preferredAppearance {
		case .inherited:
			/* Cleared before the system's appearance is read, because an
			 appearance of the application's own would answer instead. */
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

		let overridesAppKitAppearance = preferredAppearance != .inherited

		let oldProperties = properties
		let changeAppearance =
			hasResolvedAppearance == false
				|| oldProperties.appearanceType != appearanceType
				|| oldProperties.overridesAppKitAppearance != overridesAppKitAppearance

		var systemChanged = systemChanged

		if changeAppearance == false {
			if systemChanged == false {
				return
			}
		} else {
			systemChanged = false
		}

		properties = AppearancePropertyCollection(
			appearanceType: appearanceType,
			isDarkAppearance: isAppearanceDark,
			overridesAppKitAppearance: overridesAppKitAppearance
		)
		hasResolvedAppearance = true

		if preferredAppearance != .inherited {
			applyAppKitAppearance(
				isAppearanceDark
					? AppearancePropertyCollection.appKitDarkAppearance()
					: AppearancePropertyCollection.appKitLightAppearance()
			)
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
