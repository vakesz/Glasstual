/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import CoreText
import SwiftUI

/// A scene-owned alternative to the shared AppKit font panel. The selected
/// PostScript name is exactly the value persisted in `TranscriptTheme`.
struct PreferencesFontPicker: View {
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

	var body: some View {
		NavigationStack {
			VStack(spacing: 0) {
				List(filteredChoices, selection: $fontName) { choice in
					Text(verbatim: choice.displayName)
						.font(.custom(choice.id, size: 13))
						.tag(choice.id)
				}
				.searchable(text: $search)

				Divider()

				HStack {
					Text(verbatim: PreferencesStyleStrings.fontLabel)
					Spacer()
					TextField("", value: $fontSize, format: .number)
						.frame(width: 64)
					Stepper("", value: $fontSize, in: 6 ... 72, step: 1)
						.labelsHidden()
				}
				.padding()
			}
			.navigationTitle(PreferencesStyleStrings.fontChange)
			.toolbar {
				ToolbarItem(placement: .cancellationAction) {
					Button(PromptStrings.Action.cancel) { dismiss() }
				}
				ToolbarItem(placement: .confirmationAction) {
					Button(PromptStrings.Action.accept) {
						apply(fontName, CGFloat(fontSize))
						dismiss()
					}
					.disabled(fontName.isEmpty || (6 ... 72).contains(fontSize) == false)
				}
			}
		}
		.frame(minWidth: 480, minHeight: 520)
	}
}
