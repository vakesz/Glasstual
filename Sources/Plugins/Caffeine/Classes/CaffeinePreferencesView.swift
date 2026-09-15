/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2015 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 *********************************************************************** */

import SwiftUI

/// The toggle writes through the host's preference store, whose change
/// notification is what the plugin re-evaluates sleep from.
struct CaffeinePreferencesView: View {
	@AppStorage private var preventSleep: Bool

	init(defaults: UserDefaults) {
		_preventSleep = AppStorage(
			wrappedValue: FirstPartyPluginPreferences.caffeinePreventSleep.defaultValue,
			FirstPartyPluginPreferences.caffeinePreventSleep.name,
			store: defaults
		)
	}

	var body: some View {
		Form {
			Section {
				Toggle(
					String(localized: .BasicLanguage.preventSleepWhileConnected),
					isOn: $preventSleep
				)
				.toggleStyle(.switch)

				Text(String(localized: .BasicLanguage.preventSleepExplanation))
					.font(.callout)
					.foregroundStyle(.secondary)
					.fixedSize(horizontal: false, vertical: true)
			}
		}
		.formStyle(.grouped)
	}
}
