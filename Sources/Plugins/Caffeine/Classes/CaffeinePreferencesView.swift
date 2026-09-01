/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2015 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 *********************************************************************** */

import SwiftUI

enum CaffeinePreferenceKey {
	static let preventSleep = "Private Extension Store -> Caffeine Extension -> Prevent Sleep"
}

struct CaffeinePreferencesView: View {
	@AppStorage private var preventSleep: Bool
	let onPreferenceChange: () -> Void

	init(defaults: UserDefaults, onPreferenceChange: @escaping () -> Void) {
		_preventSleep = AppStorage(
			wrappedValue: false,
			CaffeinePreferenceKey.preventSleep,
			store: defaults
		)
		self.onPreferenceChange = onPreferenceChange
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
		.onChange(of: preventSleep) { _, _ in
			onPreferenceChange()
		}
	}
}
