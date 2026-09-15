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

/** The measurements the Settings window keeps.

 One 4-pt scale, in one place: the panes and the transfer sheets each used to
 pick a number of their own, and six different paddings is what that looked
 like. The window sizes live here too, because the sidebar and the widest form
 are what they are chosen against. */
enum PreferencesMetrics {
	static let spacingSmall = 4.0
	static let spacingMedium = 8.0
	static let spacingLarge = 16.0
	/// The inset around a sheet's own content, which is a window edge rather
	/// than a row gap.
	static let sheetInset = 24.0
	/// Wide enough for the longest sidebar title without leaving the detail
	/// column short of the forms it has to draw.
	static let sidebarWidth = 200.0
	/// What the window opens at: the sidebar plus a detail column that fits the
	/// widest pane without wrapping its labels.
	static let windowSize = CGSize(width: 820, height: 640)
	/// How far it can be taken in: every pane still draws, with scrolling.
	static let minimumWindowSize = CGSize(width: 720, height: 520)
}

/** The chrome a Settings detail pane wears.

 An add-on brings a `Form` of its own, which is why this is a modifier rather
 than a container: applying it to the add-on's view gives that form the same
 grouping, background and margins the application's own panes have. */
struct PreferencesFormChrome: ViewModifier {
	func body(content: Content) -> some View {
		content
			.formStyle(.grouped)
			.scrollContentBackground(.hidden)
			.contentMargins(.top, PreferencesMetrics.spacingMedium, for: .scrollContent)
	}
}

/** The grouped, independently scrolling `Form` every detail pane uses.

 Each setting is a row of its own: a `VStack` inside a grouped form counts as
 one row, so the system's separators, spacing and label alignment would apply
 to the stack rather than to the settings inside it. */
struct PreferencesPaneLayout<Content: View>: View {
	@ViewBuilder let content: Content

	var body: some View {
		Form {
			content
		}
		.modifier(PreferencesFormChrome())
	}
}

/// Explanatory text below a control, in the secondary style.
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
	/// The sentence explaining the setting, where it needs one. A grouped form
	/// draws a second label as the row's subtitle, with the system's spacing.
	var note: String?
	/** Whether the setting applies at all.

	 A switch another setting has made irrelevant reads as off, writes nothing
	 and draws disabled, all from this one condition. */
	var isEnabled = true
	@Binding var isOn: Bool

	var body: some View {
		Toggle(isOn: $isOn.gated(by: isEnabled)) {
			Text(verbatim: title)

			if let note {
				Text(verbatim: note)
			}
		}
		.toggleStyle(.switch)
		.disabled(isEnabled == false)
	}
}

/** One protocol capability the user can switch off: its wire name, what it
 does in a sentence, and a link to the document that defines it.

 The name is verbatim because it is the identifier the server and the client
 exchange; the summary is what says why anyone would keep it on. The spoken
 label is passed in already composed, so the sentence a screen reader hears is
 localized as one string rather than assembled here. */
struct PreferencesCapabilityToggle: View {
	let name: String
	let summary: String?
	let accessibilityLabel: String
	let specification: URL?
	let specificationTitle: String
	@Binding var isOn: Bool

	var body: some View {
		VStack(alignment: .leading, spacing: PreferencesMetrics.spacingSmall) {
			Toggle(isOn: $isOn) {
				VStack(alignment: .leading, spacing: 2) {
					Text(verbatim: name)
					if let summary {
						Text(verbatim: summary)
							.font(.callout)
							.foregroundStyle(.secondary)
							.fixedSize(horizontal: false, vertical: true)
					}
				}
			}
			.toggleStyle(.switch)
			.accessibilityLabel(Text(verbatim: accessibilityLabel))

			if let specification {
				Link(specificationTitle, destination: specification)
					.font(.callout)
			}
		}
		.padding(.vertical, 2)
	}
}

/// A field the user can type into, with the values the application ships
/// reachable from the pop-up beside it.
struct PreferencesComboField: View {
	private enum Storage {
		/// Every keystroke is stored.
		case live(Binding<String>)
		/// A partially typed entry has to be finished before it is stored.
		case committed(PreferencesFieldValue, rejectionMessage: String?)
	}

	let title: String
	let presets: [String]
	private let storage: Storage

	init(title: String, presets: [String], text: Binding<String>) {
		self.title = title
		self.presets = presets
		storage = .live(text)
	}

	init(title: String, presets: [String], value: PreferencesFieldValue, rejectionMessage: String? = nil) {
		self.title = title
		self.presets = presets
		storage = .committed(value, rejectionMessage: rejectionMessage)
	}

	var body: some View {
		HStack(spacing: PreferencesMetrics.spacingMedium) {
			switch storage {
			case let .live(text):
				TextField("", text: text)
					.labelsHidden()
					.accessibilityLabel(Text(verbatim: title))
			case let .committed(value, rejectionMessage):
				PreferencesCommittedField(title: title, value: value, rejectionMessage: rejectionMessage)
			}

			Menu {
				ForEach(presets, id: \.self) { preset in
					Button(preset) {
						choose(preset)
					}
				}
			} label: {
				Label(PreferencesFieldStrings.presetsHelp, systemImage: "chevron.up.chevron.down")
			}
			.labelStyle(.iconOnly)
			.menuStyle(.borderlessButton)
			.menuIndicator(.hidden)
			.fixedSize()
			.help(Text(verbatim: PreferencesFieldStrings.presetsHelp))
		}
	}

	private func choose(_ preset: String) {
		switch storage {
		case let .live(text): text.wrappedValue = preset
		case let .committed(value, _): _ = value.write(preset)
		}
	}
}

/** What a field that writes on completion edits: the stored value as text,
 and a write that says whether the store took the entry.

 The store is the judge of what it accepts, and only it knows: comparing what
 reads back with what was typed calls `08` or `+5` a rejection when the store
 simply wrote `8` and `5`. */
struct PreferencesFieldValue {
	let text: () -> String
	let write: (String) -> Bool
}

/** A field that writes when editing ends rather than as it is typed.

 A value written per keystroke reaches a store that validates it, and a store
 that refuses "2" on the way to "2000" snaps the field back mid-word. */
struct PreferencesCommittedField: View {
	let title: String
	let value: PreferencesFieldValue
	/// Shown under the field when the store refused the last entry.
	var rejectionMessage: String?

	@State private var draft = PreferencesFieldDraft()
	@FocusState private var isFocused: Bool

	var body: some View {
		VStack(alignment: .leading, spacing: PreferencesMetrics.spacingSmall) {
			TextField("", text: Binding(get: { draft.displayed(value.text()) }, set: { draft.edit($0) }))
				.labelsHidden()
				.accessibilityLabel(Text(verbatim: title))
				.focused($isFocused)
				.onSubmit { draft.commit(to: value) }
				.onChange(of: isFocused) { _, hasFocus in
					if hasFocus == false {
						draft.commit(to: value)
					}
				}

			if draft.wasRejected, let rejectionMessage {
				Text(verbatim: rejectionMessage)
					.font(.caption)
					.foregroundStyle(.red)
			}
		}
	}
}

/** What a field that writes on completion is holding.

 Nothing reaches the store while an entry is being typed, and the store is the
 judge of what it accepts: an entry it refused is one the field reports and
 then forgets. */
struct PreferencesFieldDraft {
	private var edited: String?
	private(set) var wasRejected = false

	/// What the field shows: the entry in progress, or the stored value.
	func displayed(_ stored: String) -> String {
		edited ?? stored
	}

	mutating func edit(_ newValue: String) {
		edited = newValue
	}

	mutating func commit(to value: PreferencesFieldValue) {
		guard let submitted = edited else { return }

		edited = nil
		wasRejected = value.write(submitted) == false
	}
}
