// Copyright (c) 2010 - 2018 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation

nonisolated extension Notification.Name {
	/** Posted when a preference is written through ``GlasstualUserDefaults``,
	 which includes a configuration import.

	 The raw value is the one the notification has always been posted under, and
	 a stored suppression or an exported configuration can name it, so it stays
	 as it is. */
	static let glasstualUserDefaultsDidChange = Notification.Name(
		"TPCPreferencesUserDefaultsDidChangeNotification"
	)
}

/** The `userInfo` of ``Notification/Name/glasstualUserDefaultsDidChange``.

 Declared beside the store that posts it so an observer matches the spelling the
 poster writes rather than repeating a literal that nothing checks. */
nonisolated enum PreferenceChangeNotification {
	/// The name of the preference that changed.
	static let changedKeyUserInfoKey = "changedKey"
}

/** The application's preference store.

 Nonisolated because a preference is read from both sides of the connection
 host and from the transcript renderer: `PreferenceKey.detachedValue` and
 `TranscriptController`'s historic-log filename take their own handle through
 ``suite()``, so the type cannot move onto the main actor. Nothing is shared
 across a domain to make it safe -- `UserDefaults` is not `Sendable`, and each
 domain holds a handle of its own -- and the values behind the handles are one
 suite, which Foundation synchronizes. */
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
		 sandbox's preferences container on current macOS releases. */
		private static let prepareReviewPreferences: Void = {
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

	/** The handle the main actor keeps for the lifetime of the process, so the
	 preference reads on every render path do not build one per access.

	 Foundation marks `UserDefaults` non-Sendable, which is why this is not a
	 process-wide global. It does not need to be one: a suite is a file, and a
	 second `UserDefaults` over the same suite reads and writes the same values.
	 Code outside the main actor takes its own handle from ``suite()``. */
	@MainActor
	static let container: GlasstualUserDefaults = {
		#if DEBUG
			_ = prepareReviewPreferences
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

	/** A private handle on the store, for code that is not on the main actor.

	 One suite is one file, so this reads and writes exactly what ``container``
	 does. Only object identity differs, and identity matters to nothing but KVO
	 and the `object` a notification is posted with -- neither of which anything
	 outside the main actor looks at. A caller that reads in a loop should hold
	 the handle rather than ask for one per read. */
	static func suite() -> GlasstualUserDefaults {
		#if DEBUG
			_ = prepareReviewPreferences
		#endif

		return GlasstualUserDefaults(storageSuiteName: storageSuiteName)
	}

	func setObjectWithoutNotification(_ value: Any?, forKey defaultName: String) {
		super.set(value, forKey: defaultName)
	}

	override func set(_ value: Any?, forKey defaultName: String) {
		set(value, forKey: defaultName, postNotification: true)
	}

	/** What the suite has persisted for `defaultName`, with no fall-through to
	 the registration domain.

	 Read straight from the current-user, any-host source, which is the one a
	 suite writes to. `persistentDomain(forName:)` answers the same question but
	 also opens the any-user, by-host source, which cfprefsd refuses for an app
	 group container and detaches from with a warning on every write. */
	func persistedObject(forKey defaultName: String) -> Any? {
		CFPreferencesCopyValue(
			defaultName as CFString,
			suiteName as CFString,
			kCFPreferencesCurrentUser,
			kCFPreferencesAnyHost
		)
	}

	func set(_ value: Any?, forKey defaultName: String, postNotification: Bool) {
		/* Compared against the persisted value, not `object(forKey:)`: the
		 latter falls through to the registration domain, so writing a value that
		 happened to equal the shipped default returned early and nothing was
		 persisted. The user's explicit choice then looked like "never touched"
		 and would silently follow a change to the default in a later release. */
		let oldValue = persistedObject(forKey: defaultName)
		if let oldValue = oldValue as? NSObject, oldValue.isEqual(value) {
			return
		}

		willChangeValue(forKey: defaultName)
		if value != nil || oldValue != nil {
			setObjectWithoutNotification(value, forKey: defaultName)
		}
		didChangeValue(forKey: defaultName)

		guard postNotification else { return }
		NotificationCenter.default.post(
			name: .glasstualUserDefaultsDidChange,
			object: self,
			userInfo: [PreferenceChangeNotification.changedKeyUserInfoKey: defaultName]
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

	func registerDefault(_ value: NSCopying, forKey defaultName: String) {
		register(defaults: [defaultName: value])
	}

	/// The registration domain, narrowed out of the `Any` the volatile domain
	/// hands back.
	var registeredDefaults: [String: PropertyListValue] {
		[String: PropertyListValue](
			propertyList: volatileDomain(forName: UserDefaults.registrationDomain)
		) ?? [:]
	}
}
