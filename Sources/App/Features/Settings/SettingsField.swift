// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import SwiftUI

/** What a field that writes on completion edits: the stored value as text,
 and a write that says whether the store took the entry.

 The store is the judge of what it accepts, and only it knows: comparing what
 reads back with what was typed calls `08` or `+5` a rejection when the store
 simply wrote `8` and `5`. */
struct SettingsFieldValue {
	let text: () -> String
	let write: (String) -> Bool
}

/** What a field that writes on completion is holding.

 Nothing reaches the store while an entry is being typed, and the store is the
 judge of what it accepts: an entry it refused is one the field reports and
 then forgets. */
struct SettingsFieldDraft {
	private var edited: String?
	private(set) var wasRejected = false

	/// What the field shows: the entry in progress, or the stored value.
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
}

/** A field that writes when editing ends rather than as it is typed.

 A value written per keystroke reaches a store that validates it, and a store
 that refuses "2" on the way to "2000" snaps the field back mid-word. */
struct SettingsCommittedField: View {
	let title: LocalizedStringResource
	let value: SettingsFieldValue
	/// Shown under the field when the store refused the last entry.
	var rejectionMessage: LocalizedStringResource?

	@State private var draft = SettingsFieldDraft()
	@FocusState private var isFocused: Bool

	var body: some View {
		VStack(alignment: .leading, spacing: UISpacing.tight) {
			TextField("", text: Binding(get: { draft.displayed(value.text()) }, set: { draft.edit($0) }))
				.labelsHidden()
				.accessibilityLabel(Text(title))
				.focused($isFocused)
				.onSubmit { draft.commit(to: value) }
				.onChange(of: isFocused) { _, hasFocus in
					if hasFocus == false {
						draft.commit(to: value)
					}
				}

			if draft.wasRejected, let rejectionMessage {
				Text(rejectionMessage)
					.font(.caption)
					.foregroundStyle(.red)
			}
		}
	}
}

/// A field the user can type into, with the values the application ships
/// reachable from the pop-up beside it.
struct SettingsComboField: View {
	private enum Storage {
		/// Every keystroke is stored.
		case live(Binding<String>)
		/// A partially typed entry has to be finished before it is stored.
		case committed(SettingsFieldValue, rejectionMessage: LocalizedStringResource?)
	}

	let title: LocalizedStringResource
	let presets: [String]
	private let storage: Storage

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
				SettingsCommittedField(title: title, value: value, rejectionMessage: rejectionMessage)
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
			.help(Text(.Settings.comboPresetsHelp))
		}
	}

	private func choose(_ preset: String) {
		switch storage {
		case let .live(text): text.wrappedValue = preset
		case let .committed(value, _): _ = value.write(preset)
		}
	}
}
