// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import SwiftUI

/// Provides the stored text and a write operation that reports validation success.
/// The write result distinguishes rejected input from accepted normalization, such as `08` to `8`.
struct SettingsFieldValue {
	let text: () -> String
	let write: (String) -> Bool
}

/// Holds uncommitted text and the result of the last validation attempt.
struct SettingsFieldDraft {
	let identifier = UUID()
	private var edited: String?
	private(set) var wasRejected = false

	/// Shows the draft until completion, then the current stored value.
	func displayed(_ stored: String) -> String {
		edited ?? stored
	}

	mutating func edit(_ newValue: String) {
		edited = newValue
	}

	mutating func commit(to value: SettingsFieldValue) {
		guard let submitted = edited else { return }

		edited = nil
		wasRejected = value.write(submitted) == false
	}

	/// Choosing a preset replaces an unfinished entry before writing it, so
	/// a later Return or focus loss cannot submit the discarded text.
	mutating func choose(_ preset: String, for value: SettingsFieldValue) {
		edited = preset
		commit(to: value)
	}
}

/// Validates when editing ends so incomplete input, such as `2` on the way to `2000`, remains editable.
struct SettingsCommittedField: View {
	let title: LocalizedStringResource
	let value: SettingsFieldValue
	/// Shown when validation rejects the last entry.
	var rejectionMessage: LocalizedStringResource?

	@State private var draft = SettingsFieldDraft()

	var body: some View {
		SettingsCommittedInput(title: title, value: value, rejectionMessage: rejectionMessage, draft: $draft)
	}
}

/// A standalone field owns its draft, while a combo shares its draft with
/// the preset menu. Both use the same completion and rejection behavior.
private struct SettingsCommittedInput: View {
	let title: LocalizedStringResource
	let value: SettingsFieldValue
	let rejectionMessage: LocalizedStringResource?
	@Binding var draft: SettingsFieldDraft
	@FocusState private var isFocused: Bool

	var body: some View {
		VStack(alignment: .leading, spacing: UISpacing.tight) {
			TextField("", text: Binding(get: { draft.displayed(value.text()) }, set: edit))
				.labelsHidden()
				.accessibilityLabel(Text(title))
				.focused($isFocused)
				.onSubmit(finishEditing)
				.onChange(of: isFocused) { _, hasFocus in
					if hasFocus == false {
						finishEditing()
					}
				}
				// A pane can leave the hierarchy before focus changes are delivered.
				.onDisappear(perform: finishEditing)

			if draft.wasRejected, let rejectionMessage {
				Text(rejectionMessage)
					.font(.caption)
					.foregroundStyle(.red)
			}
		}
	}

	private func edit(_ text: String) {
		SettingsEditingSession.shared.track(draft.identifier) { draft.commit(to: value) }
		draft.edit(text)
	}

	private func finishEditing() {
		SettingsEditingSession.shared.finishEditing(for: draft.identifier)
	}
}

/// An editable field with a preset menu.
struct SettingsComboField: View {
	private enum Storage {
		/// Every keystroke is stored.
		case live(Binding<String>)
		/// Store the value when editing ends.
		case committed(SettingsFieldValue, rejectionMessage: LocalizedStringResource?)
	}

	let title: LocalizedStringResource
	let presets: [String]
	private let storage: Storage
	@State private var draft = SettingsFieldDraft()

	init(title: LocalizedStringResource, presets: [String], text: Binding<String>) {
		self.title = title
		self.presets = presets
		storage = .live(text)
	}

	init(
		title: LocalizedStringResource,
		presets: [String],
		value: SettingsFieldValue,
		rejectionMessage: LocalizedStringResource? = nil
	) {
		self.title = title
		self.presets = presets
		storage = .committed(value, rejectionMessage: rejectionMessage)
	}

	var body: some View {
		HStack(spacing: UISpacing.regular) {
			switch storage {
			case let .live(text):
				TextField("", text: text)
					.labelsHidden()
					.accessibilityLabel(Text(title))
			case let .committed(value, rejectionMessage):
				SettingsCommittedInput(title: title, value: value, rejectionMessage: rejectionMessage, draft: $draft)
			}

			Menu {
				ForEach(presets, id: \.self) { preset in
					Button(preset) {
						choose(preset)
					}
				}
			} label: {
				Label {
					Text(.Settings.comboPresetsHelp)
				} icon: {
					Image(systemName: "chevron.up.chevron.down")
				}
			}
			.labelStyle(.iconOnly)
			.menuStyle(.borderlessButton)
			.menuIndicator(.hidden)
			.fixedSize()
			.accessibilityLabel(Text(title))
			.help(Text(.Settings.comboPresetsHelp))
		}
	}

	private func choose(_ preset: String) {
		switch storage {
		case let .live(text): text.wrappedValue = preset
		case let .committed(value, _):
			draft.choose(preset, for: value)
			SettingsEditingSession.shared.finishEditing(for: draft.identifier)
		}
	}
}
