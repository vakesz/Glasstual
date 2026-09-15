/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import Foundation

/** Calls a plugin back when one of the preferences it reads is written.

 Every write through the application's preference store posts
 `FirstPartyPluginPreferences.defaultsDidChangeNotification` naming the key,
 including the writes a plugin's own pane makes and a configuration import, so
 that one notification is observed and filtered to the plugin's keys. The
 Foundation notification it used to observe as well fires for every write to
 any key, with no name attached, and a second time for each of these. A
 notification that names no key is taken to mean anything may have changed.
 Plugin callbacks read the effective values on the main actor rather than
 transferring `UserDefaults` between actors. */
@MainActor
final class PluginDefaultsObservation {
	private let task: Task<Void, Never>

	/// Starts observing before returning, so a write that follows cannot be missed.
	init(keys: Set<String>, using handler: @escaping @MainActor () -> Void) {
		let notifications = NotificationCenter.default.notifications(
			named: FirstPartyPluginPreferences.defaultsDidChangeNotification
		)
		task = Task { @MainActor in
			for await notification in notifications {
				guard Task.isCancelled == false else { return }
				let changedKey = notification.userInfo?[FirstPartyPluginPreferences.changedKeyUserInfoKey] as? String
				if let changedKey, keys.contains(changedKey) == false {
					continue
				}
				handler()
			}
		}
	}

	isolated deinit {
		task.cancel()
	}
}
