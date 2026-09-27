// Copyright (c) 2010 - 2018 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation

nonisolated extension Notification.Name {
	/// Posted when a setting is written through ``GlasstualUserDefaults``,
	/// which includes a configuration import.
	static let userDefaultsDidChange = Notification.Name(
		"Glasstual.userDefaultsDidChange"
	)
}

/// Shared `userInfo` keys for `Notification.Name.userDefaultsDidChange`.
nonisolated enum SettingsChangeNotification {
	/// The name of the setting that changed.
	static let changedKeyUserInfoKey = "changedKey"
}

/// The main actor, transcript renderer and scrollback actor use separate
/// `UserDefaults` handles to one Foundation-synchronized settings suite.
/// Handles remain in their owning isolation domain; the connection host reads no settings.
final nonisolated class GlasstualUserDefaults: UserDefaults { // nonisolated: guarded
	private static let storageSuiteName: String = {
		#if DEBUG
			if let reviewSuite = ProcessInfo.processInfo.environment["GLASSTUAL_UI_REVIEW_SUITE"],
			   !reviewSuite.isEmpty
			{
				return reviewSuite
			}
		#endif

		return ApplicationGroup.identifier
	}()

	#if DEBUG
		/** Installs an E2E fixture from inside the app sandbox before any handle
		 to its isolated review suite is opened. The harness cannot write another
		 sandbox's settings container on current macOS releases. */
		private static let prepareReviewSettings: Void = {
			guard
				let encoded = ProcessInfo.processInfo.environment["GLASSTUAL_UI_REVIEW_PREFERENCES"],
				let data = Data(base64Encoded: encoded),
				let propertyList = try? PropertyListSerialization.propertyList(from: data, format: nil),
				let domain = propertyList as? [String: Any],
				let defaults = UserDefaults(suiteName: storageSuiteName)
			else { return }

			defaults.setPersistentDomain(domain, forName: storageSuiteName)
		}()
	#endif

	/// Reuses one handle for main-actor reads. Other isolation domains use `suite()`.
	@MainActor
	static let container: GlasstualUserDefaults = {
		#if DEBUG
			_ = prepareReviewSettings
		#endif

		return GlasstualUserDefaults(storageSuiteName: storageSuiteName)
	}()

	/// The suite this instance is bound to, kept because `UserDefaults` does not
	/// expose it and the persisted-value reads need it.
	let suiteName: String

	private init(storageSuiteName: String) {
		suiteName = storageSuiteName
		super.init(suiteName: storageSuiteName)!
	}

	override convenience init?(suiteName _: String?) {
		self.init(storageSuiteName: Self.storageSuiteName)
	}

	/// Creates a handle for the caller's isolation domain. Reuse it within a read loop.
	static func suite() -> GlasstualUserDefaults {
		#if DEBUG
			_ = prepareReviewSettings
		#endif

		return GlasstualUserDefaults(storageSuiteName: storageSuiteName)
	}

	/// Reads persisted data without registration defaults. The current-user,
	/// any-host source avoids the unsupported app-group lookup performed by `persistentDomain(forName:)`.
	func persistedObject(forKey defaultName: String) -> Any? {
		CFPreferencesCopyValue(
			defaultName as CFString,
			suiteName as CFString,
			kCFPreferencesCurrentUser,
			kCFPreferencesAnyHost
		)
	}

	override func set(_ value: Any?, forKey defaultName: String) {
		// Compare persisted values so an explicit choice equal to the registered
		// default is still saved and survives future changes to that default.
		let oldValue = persistedObject(forKey: defaultName)
		if let oldValue = oldValue as? NSObject, oldValue.isEqual(value) {
			return
		}

		willChangeValue(forKey: defaultName)
		if value != nil || oldValue != nil {
			super.set(value, forKey: defaultName)
		}
		didChangeValue(forKey: defaultName)

		NotificationCenter.default.post(
			name: .userDefaultsDidChange,
			object: self,
			userInfo: [SettingsChangeNotification.changedKeyUserInfoKey: defaultName]
		)
	}

	override func set(_ value: Int, forKey defaultName: String) {
		set(NSNumber(value: value), forKey: defaultName)
	}

	override func set(_ value: Float, forKey defaultName: String) {
		set(NSNumber(value: value), forKey: defaultName)
	}

	override func set(_ value: Double, forKey defaultName: String) {
		set(NSNumber(value: value), forKey: defaultName)
	}

	override func set(_ value: Bool, forKey defaultName: String) {
		set(NSNumber(value: value), forKey: defaultName)
	}

	override func set(_ url: URL?, forKey defaultName: String) {
		set(url as Any?, forKey: defaultName)
	}

	override func removeObject(forKey defaultName: String) {
		set(nil, forKey: defaultName)
	}

	/// Registered defaults represented as property-list values.
	var registeredDefaults: [String: PropertyListValue] {
		[String: PropertyListValue](
			propertyList: volatileDomain(forName: UserDefaults.registrationDomain)
		) ?? [:]
	}
}
