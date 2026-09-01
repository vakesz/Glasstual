/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2013 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 *********************************************************************** */

import SwiftUI

enum SmileyConverterPreferenceKey {
	static let serviceEnabled = "Smiley Converter Extension -> Enable Service"
	static let extraEmoticonsEnabled = "Smiley Converter Extension -> Enable Extra Emoticons"
}

struct SmileyConverterPreferencesView: View {
	@AppStorage private var serviceEnabled: Bool
	@AppStorage private var extraEmoticonsEnabled: Bool
	let onPreferenceChange: () -> Void

	init(defaults: UserDefaults, onPreferenceChange: @escaping () -> Void) {
		_serviceEnabled = AppStorage(
			wrappedValue: false,
			SmileyConverterPreferenceKey.serviceEnabled,
			store: defaults
		)
		_extraEmoticonsEnabled = AppStorage(
			wrappedValue: false,
			SmileyConverterPreferenceKey.extraEmoticonsEnabled,
			store: defaults
		)
		self.onPreferenceChange = onPreferenceChange
	}

	var body: some View {
		Form {
			Section {
				Text(String(localized: .BasicLanguage.smileyConverterExplanation))
					.fixedSize(horizontal: false, vertical: true)
			}

			Section {
				Toggle(
					String(localized: .BasicLanguage.enableService),
					isOn: $serviceEnabled
				)
				.toggleStyle(.switch)

				Toggle(
					String(localized: .BasicLanguage.enableExtraEmoticons),
					isOn: $extraEmoticonsEnabled
				)
				.toggleStyle(.switch)
				.disabled(serviceEnabled == false)
			}
		}
		.formStyle(.grouped)
		.onChange(of: serviceEnabled) { _, _ in
			onPreferenceChange()
		}
		.onChange(of: extraEmoticonsEnabled) { _, _ in
			onPreferenceChange()
		}
	}
}
