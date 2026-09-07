/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import Foundation

/// Defaults can change through another handle or an imported configuration.
/// Register before returning; plugin callbacks read the effective values on
/// the main actor rather than transferring UserDefaults between actors.
@MainActor
final class PluginDefaultsObservation {
	private var tasks: [Task<Void, Never>] = []

	init(using handler: @escaping @MainActor () -> Void) {
		let names = [
			UserDefaults.didChangeNotification,
			FirstPartyPluginPreferences.defaultsDidChangeNotification,
		]
		for name in names {
			let notifications = NotificationCenter.default.notifications(named: name)
			tasks.append(Task { @MainActor in
				for await _ in notifications {
					guard Task.isCancelled == false else { return }
					handler()
				}
			})
		}
	}

	isolated deinit {
		tasks.forEach { $0.cancel() }
	}
}
