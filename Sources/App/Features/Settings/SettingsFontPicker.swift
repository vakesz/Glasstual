// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CoreText
import SwiftUI

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
					.padding(.horizontal, SettingsWindowMetrics.sheetInset)
					.padding(.vertical, UISpacing.loose)

				Divider()

				HStack(spacing: UISpacing.regular) {
					Spacer()
					Button(PromptStrings.Action.cancel) { dismiss() }
						.keyboardShortcut(.cancelAction)
					Button(.Settings.styleFontPickerChoose) {
						apply(fontName, CGFloat(fontSize))
						dismiss()
					}
					.keyboardShortcut(.defaultAction)
					.disabled(canApply == false)
				}
				.padding(SettingsWindowMetrics.sheetInset)
			}
			.navigationTitle(Text(.Settings.styleFontPickerTitle))
		}
		.frame(minWidth: 480, minHeight: 520)
	}

	private var sizeRow: some View {
		LabeledContent {
			HStack(spacing: UISpacing.tight) {
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
