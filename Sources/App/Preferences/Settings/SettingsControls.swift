// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
import CoreText
import SwiftUI

/** The measurements the Settings window keeps.

 One 4-pt scale, in one place: the panes and the transfer sheets each used to
 pick a number of their own, and six different paddings is what that looked
 like. The window sizes live here too, because the sidebar and the widest form
 are what they are chosen against. */
enum SettingsMetrics {
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

 A modifier rather than a container, so a pane that brings a `Form` of its own
 gets the same grouping, background and margins as the rest. */
struct SettingsFormChrome: ViewModifier {
	func body(content: Content) -> some View {
		content
			.formStyle(.grouped)
			.scrollContentBackground(.hidden)
			.contentMargins(.top, SettingsMetrics.spacingMedium, for: .scrollContent)
	}
}

/** The grouped, independently scrolling `Form` every detail pane uses.

 Each setting is a row of its own: a `VStack` inside a grouped form counts as
 one row, so the system's separators, spacing and label alignment would apply
 to the stack rather than to the settings inside it. */
struct SettingsPaneLayout<Content: View>: View {
	@ViewBuilder let content: Content

	var body: some View {
		Form {
			content
		}
		.modifier(SettingsFormChrome())
	}
}

extension Binding where Value == Bool {
	/** Reads as off and writes nothing while `isEnabled` is false.

	 A setting another setting has made irrelevant has one condition behind it,
	 so the switch cannot read as on while it is drawn disabled. */
	func gated(by isEnabled: Bool) -> Binding<Bool> {
		let stored = self

		return Binding(
			get: { isEnabled && stored.wrappedValue },
			set: { newValue in
				guard isEnabled else { return }
				stored.wrappedValue = newValue
			}
		)
	}
}

/// Explanatory text below a control, in the secondary style.
struct SettingsNote: View {
	let text: LocalizedStringResource

	init(_ text: LocalizedStringResource) {
		self.text = text
	}

	var body: some View {
		Text(text)
			.font(.callout)
			.foregroundStyle(.secondary)
			.fixedSize(horizontal: false, vertical: true)
			.frame(maxWidth: .infinity, alignment: .leading)
	}
}

/// A native settings switch driven by a typed preference binding.
struct SettingsToggle: View {
	let title: LocalizedStringResource
	/// The sentence explaining the setting, where it needs one. A grouped form
	/// draws a second label as the row's subtitle, with the system's spacing.
	var note: LocalizedStringResource?
	/** Whether the setting applies at all.

	 A switch another setting has made irrelevant reads as off, writes nothing
	 and draws disabled, all from this one condition. */
	var isEnabled = true
	@Binding var isOn: Bool

	var body: some View {
		Toggle(isOn: $isOn.gated(by: isEnabled)) {
			Text(title)

			if let note {
				Text(note)
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
struct SettingsCapabilityToggle: View {
	let name: String
	let summary: LocalizedStringResource?
	let accessibilityLabel: String
	let specification: URL?
	let specificationTitle: LocalizedStringResource
	@Binding var isOn: Bool

	var body: some View {
		VStack(alignment: .leading, spacing: SettingsMetrics.spacingSmall) {
			Toggle(isOn: $isOn) {
				VStack(alignment: .leading, spacing: 2) {
					Text(verbatim: name)
					if let summary {
						Text(summary)
							.font(.callout)
							.foregroundStyle(.secondary)
							.fixedSize(horizontal: false, vertical: true)
					}
				}
			}
			.toggleStyle(.switch)
			.accessibilityLabel(Text(verbatim: accessibilityLabel))

			if let specification {
				Link(destination: specification) {
					Text(specificationTitle)
				}
				.font(.callout)
			}
		}
		.padding(.vertical, 2)
	}
}

/// A folder picker: the chosen folder with its icon, plus the two commands
/// that change it.
struct SettingsFolderPicker: View {
	let label: LocalizedStringResource
	let accessibilityLabel: LocalizedStringResource
	let folder: URL?
	let emptyTitle: LocalizedStringResource
	let clearTitle: LocalizedStringResource
	let canClear: Bool
	let select: () -> Void
	let clear: () -> Void

	init(
		label: LocalizedStringResource,
		accessibilityLabel: LocalizedStringResource,
		folder: URL?,
		emptyTitle: LocalizedStringResource,
		clearTitle: LocalizedStringResource = .Settings.logLocationClearDestination,
		canClear: Bool? = nil,
		select: @escaping () -> Void,
		clear: @escaping () -> Void
	) {
		self.label = label
		self.accessibilityLabel = accessibilityLabel
		self.folder = folder
		self.emptyTitle = emptyTitle
		self.clearTitle = clearTitle
		self.canClear = canClear ?? (folder != nil)
		self.select = select
		self.clear = clear
	}

	var body: some View {
		LabeledContent {
			Menu {
				Button(action: select) {
					Text(.Settings.logLocationSelectDestination)
				}
				Button(action: clear) {
					Text(clearTitle)
				}
				.disabled(canClear == false)
			} label: {
				HStack(spacing: 4) {
					if let folder {
						Image(nsImage: NSWorkspace.shared.icon(forFile: folder.path))
							.resizable()
							.frame(width: 16, height: 16)
						Text(verbatim: folder.lastPathComponent)
					} else {
						Text(emptyTitle)
					}
				}
			}
			.accessibilityLabel(Text(accessibilityLabel))
		} label: {
			Text(label)
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
		HStack(spacing: SettingsMetrics.spacingMedium) {
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

/** What a field that writes on completion edits: the stored value as text,
 and a write that says whether the store took the entry.

 The store is the judge of what it accepts, and only it knows: comparing what
 reads back with what was typed calls `08` or `+5` a rejection when the store
 simply wrote `8` and `5`. */
struct SettingsFieldValue {
	let text: () -> String
	let write: (String) -> Bool
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
		VStack(alignment: .leading, spacing: SettingsMetrics.spacingSmall) {
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

/// A scene-owned alternative to the shared AppKit font panel. The selected
/// PostScript name is exactly the value persisted in `TranscriptTheme`.
struct SettingsFontPicker: View {
	private struct FontChoice: Identifiable {
		let id: String
		let displayName: String
	}

	private static let choices: [FontChoice] = {
		let names = CTFontManagerCopyAvailablePostScriptNames() as? [String] ?? []
		return names.map { name in
			let font = CTFontCreateWithName(name as CFString, 13, nil)
			return FontChoice(id: name, displayName: CTFontCopyDisplayName(font) as String)
		}
		.sorted {
			$0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
		}
	}()

	/// The transcript renderer's own bounds: a size outside them is rejected
	/// when the theme is applied, so it is not offered here.
	private static let sizeRange = Double(TranscriptTheme.fontSizeRange.lowerBound)
		... Double(TranscriptTheme.fontSizeRange.upperBound)

	/// What the list draws each name in. A 6-point row is unreadable and a
	/// 72-point one scrolls one font at a time, so the preview follows the
	/// chosen size only as far as it stays a list.
	private static let previewSizeRange = 11.0 ... 24.0

	@Environment(\.dismiss) private var dismiss
	@State private var fontName: String
	@State private var fontSize: Double
	@State private var search = ""

	let apply: (String, CGFloat) -> Void

	init(fontName: String, fontSize: CGFloat, apply: @escaping (String, CGFloat) -> Void) {
		_fontName = State(initialValue: fontName)
		_fontSize = State(initialValue: Double(fontSize))
		self.apply = apply
	}

	private var filteredChoices: [FontChoice] {
		guard search.isEmpty == false else { return Self.choices }
		return Self.choices.filter {
			$0.displayName.localizedCaseInsensitiveContains(search)
				|| $0.id.localizedCaseInsensitiveContains(search)
		}
	}

	private var previewSize: Double {
		min(max(fontSize, Self.previewSizeRange.lowerBound), Self.previewSizeRange.upperBound)
	}

	private var canApply: Bool {
		fontName.isEmpty == false && Self.sizeRange.contains(fontSize)
	}

	var body: some View {
		NavigationStack {
			VStack(spacing: 0) {
				List(filteredChoices, selection: $fontName) { choice in
					Text(verbatim: choice.displayName)
						.font(.custom(choice.id, size: previewSize))
						.tag(choice.id)
				}
				.searchable(text: $search)

				Divider()

				sizeRow
					.padding(.horizontal, SettingsMetrics.sheetInset)
					.padding(.vertical, SettingsMetrics.spacingLarge)

				Divider()

				HStack(spacing: SettingsMetrics.spacingMedium) {
					Spacer()
					Button(PromptStrings.Action.cancel) { dismiss() }
						.keyboardShortcut(.cancelAction)
					Button(String(localized: .Settings.styleFontPickerChoose)) {
						apply(fontName, CGFloat(fontSize))
						dismiss()
					}
					.keyboardShortcut(.defaultAction)
					.disabled(canApply == false)
				}
				.padding(SettingsMetrics.sheetInset)
			}
			.navigationTitle(Text(.Settings.styleFontPickerTitle))
		}
		.frame(minWidth: 480, minHeight: 520)
	}

	private var sizeRow: some View {
		LabeledContent {
			HStack(spacing: SettingsMetrics.spacingSmall) {
				TextField("", value: $fontSize, format: .number)
					.labelsHidden()
					.frame(width: 64)
					.accessibilityLabel(Text(.Settings.styleFontSizeLabel))
				Stepper(value: $fontSize, in: Self.sizeRange, step: 1) {
					EmptyView()
				}
				.labelsHidden()
				.accessibilityLabel(Text(.Settings.styleFontSizeLabel))
				Spacer()
			}
		} label: {
			Text(.Settings.styleFontSizeLabel)
		}
	}
}
