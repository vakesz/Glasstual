/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2010 - 2018 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 *
 *  * Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 *  * Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 *  * Neither the name of Textual, "Codeux Software, LLC", nor the
 *    names of its contributors may be used to endorse or promote products
 *    derived from this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED. IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
 * FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
 * OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
 * LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
 * OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
 * SUCH DAMAGE.
 *
 *********************************************************************** */

import CocoaExtensions
import Foundation

public nonisolated extension Notification.Name { // nonisolated: value
	static let textualUserDefaultsDidChange = Self("TPCPreferencesUserDefaultsDidChangeNotification")
}

/** The application's preference store.

 Nonisolated because a preference is read from both sides of the connection
 host and from the transcript renderer: `PreferenceKey.detachedDefaults` and
 `LogController`'s historic-log filename take their own handle through
 ``suite()``, so the type cannot move onto the main actor. Nothing is shared
 across a domain to make it safe -- `UserDefaults` is not `Sendable`, and each
 domain holds a handle of its own -- and the values behind the handles are one
 suite, which Foundation synchronizes. */
public final nonisolated class TextualUserDefaults: UserDefaults { // nonisolated: guarded
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

	/** The handle the main actor keeps for the lifetime of the process, so the
	 preference reads on every render path do not build one per access.

	 Foundation marks `UserDefaults` non-Sendable, which is why this is not a
	 process-wide global. It does not need to be one: a suite is a file, and a
	 second `UserDefaults` over the same suite reads and writes the same values.
	 Code outside the main actor takes its own handle from ``suite()``. */
	@MainActor
	public static let container = TextualUserDefaults(storageSuiteName: storageSuiteName)

	/// The suite this instance is bound to, kept because `UserDefaults` does not
	/// expose it and the persisted-value reads need it.
	public let suiteName: String

	private init(storageSuiteName: String) {
		suiteName = storageSuiteName
		super.init(suiteName: storageSuiteName)!
	}

	override public convenience init?(suiteName _: String?) {
		self.init(storageSuiteName: Self.storageSuiteName)
	}

	/** A private handle on the store, for code that is not on the main actor.

	 One suite is one file, so this reads and writes exactly what ``container``
	 does. Only object identity differs, and identity matters to nothing but KVO
	 and the `object` a notification is posted with -- neither of which anything
	 outside the main actor looks at. A caller that reads in a loop should hold
	 the handle rather than ask for one per read. */
	public static func suite() -> TextualUserDefaults {
		TextualUserDefaults(storageSuiteName: storageSuiteName)
	}

	public func setObjectWithoutNotification(_ value: Any?, forKey defaultName: String) {
		super.set(value, forKey: defaultName)
	}

	override public func set(_ value: Any?, forKey defaultName: String) {
		set(value, forKey: defaultName, postNotification: true)
	}

	/** What the suite has persisted for `defaultName`, with no fall-through to
	 the registration domain.

	 Read straight from the current-user, any-host source, which is the one a
	 suite writes to. `persistentDomain(forName:)` answers the same question but
	 also opens the any-user, by-host source, which cfprefsd refuses for an app
	 group container and detaches from with a warning on every write. */
	public func persistedObject(forKey defaultName: String) -> Any? {
		CFPreferencesCopyValue(
			defaultName as CFString,
			suiteName as CFString,
			kCFPreferencesCurrentUser,
			kCFPreferencesAnyHost
		)
	}

	/// Every key the suite has persisted, with no registration-domain values.
	public func persistedValues() -> [String: Any] {
		CFPreferencesCopyMultiple(
			nil,
			suiteName as CFString,
			kCFPreferencesCurrentUser,
			kCFPreferencesAnyHost
		) as? [String: Any] ?? [:]
	}

	public func set(_ value: Any?, forKey defaultName: String, postNotification: Bool) {
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
			name: .textualUserDefaultsDidChange,
			object: self,
			userInfo: ["changedKey": defaultName]
		)
	}

	override public func set(_ value: Int, forKey defaultName: String) {
		set(NSNumber(value: value), forKey: defaultName)
	}

	override public func set(_ value: Float, forKey defaultName: String) {
		set(NSNumber(value: value), forKey: defaultName)
	}

	override public func set(_ value: Double, forKey defaultName: String) {
		set(NSNumber(value: value), forKey: defaultName)
	}

	override public func set(_ value: Bool, forKey defaultName: String) {
		set(NSNumber(value: value), forKey: defaultName)
	}

	override public func set(_ url: URL?, forKey defaultName: String) {
		set(url as Any?, forKey: defaultName)
	}

	override public func removeObject(forKey defaultName: String) {
		set(nil, forKey: defaultName)
	}

	public func registerDefault(_ value: NSCopying, forKey defaultName: String) {
		register(defaults: [defaultName: value])
	}

	/// The registration domain, narrowed out of the `Any` the volatile domain
	/// hands back.
	public var registeredDefaults: [String: PropertyListValue] {
		[String: PropertyListValue](
			propertyList: volatileDomain(forName: UserDefaults.registrationDomain)
		) ?? [:]
	}
}
