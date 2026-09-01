/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 *********************************************************************** */

import SwiftUI

/// The grouped, independently scrolling `Form` every detail pane uses.
struct PreferencesPaneLayout<Content: View>: View {
	@ViewBuilder let content: Content

	var body: some View {
		Form {
			content
		}
		.formStyle(.grouped)
		.scrollContentBackground(.hidden)
		.contentMargins(.top, 8, for: .scrollContent)
	}
}

/// Explanatory text below a control, in the secondary style the nib used.
struct PreferencesNote: View {
	let text: String

	init(_ text: String) {
		self.text = text
	}

	var body: some View {
		Text(verbatim: text)
			.font(.callout)
			.foregroundStyle(.secondary)
			.fixedSize(horizontal: false, vertical: true)
			.frame(maxWidth: .infinity, alignment: .leading)
	}
}

/// A native settings switch driven by a typed preference binding.
struct PreferencesToggle: View {
	let title: String
	@Binding var isOn: Bool

	var body: some View {
		Toggle(isOn: $isOn) {
			Text(verbatim: title)
		}
		.toggleStyle(.switch)
	}
}

/** The nib's combo boxes: a field the user can type into, with the list of
 values it shipped reachable from the button beside it. */
struct PreferencesComboField: View {
	let title: String
	let presets: [String]
	@Binding var text: String

	var body: some View {
		HStack(spacing: 6) {
			TextField("", text: $text)
				.labelsHidden()
				.accessibilityLabel(Text(verbatim: title))
			Menu {
				ForEach(presets, id: \.self) { preset in
					Button(preset) {
						text = preset
					}
				}
			} label: {
				EmptyView()
			}
			.menuStyle(.borderlessButton)
			.frame(width: 16)
			.accessibilityLabel(Text(verbatim: title))
		}
	}
}
