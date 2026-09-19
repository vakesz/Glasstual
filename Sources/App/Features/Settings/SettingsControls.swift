// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
import SwiftUI

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

/// A native settings switch driven by a typed setting binding.
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
