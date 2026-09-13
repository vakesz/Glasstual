/* *********************************************************************
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import AppKit
import SwiftUI

@MainActor
struct NicknameColorView: View {
	@Bindable var model: NicknameColorModel
	let changeColor: @MainActor () -> Void
	let cancel: @MainActor () -> Void

	private var selectedColor: Binding<Color> {
		Binding(
			get: { Color(nsColor: model.selectedColor) },
			set: { model.selectColor(NSColor($0)) }
		)
	}

	private var usesDefaultColor: Binding<Bool> {
		Binding(
			get: { model.usesDefaultColor },
			set: model.setUsesDefaultColor
		)
	}

	var body: some View {
		VStack(alignment: .leading, spacing: UISpacing.loose) {
			Text(verbatim: NicknameColorStrings.windowTitle(nickname: model.nickname))
				.font(.headline)

			/* The nickname as the transcript will draw it, in the colour being
			 chosen: a swatch in a picker says nothing about whether the name is
			 legible where it is read. */
			Text(verbatim: model.nickname)
				.font(.body.weight(.semibold))
				.foregroundStyle(Color(nsColor: model.previewColor))
				.lineLimit(1)
				.truncationMode(.tail)
				.frame(maxWidth: .infinity, alignment: .leading)
				.padding(.vertical, UISpacing.regular)
				.padding(.horizontal, UISpacing.wide)
				.background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
				.accessibilityLabel(
					NicknameColorStrings.previewAccessibilityLabel(nickname: model.nickname)
				)

			HStack(spacing: UISpacing.wide) {
				ColorPicker(NicknameColorStrings.colorPickerLabel, selection: selectedColor)
					.disabled(model.usesDefaultColor)
					.accessibilityHint(Text(verbatim: NicknameColorStrings.colorPickerAccessibilityHint))

				Toggle(isOn: usesDefaultColor) {
					Text(verbatim: NicknameColorStrings.useDefaultColorTitle)
				}
				.accessibilityHint(Text(verbatim: NicknameColorStrings.useDefaultColorAccessibilityHint))
			}

			HStack(spacing: UISpacing.regular) {
				Spacer()

				Button(PromptStrings.Action.cancel, action: cancel)
					.keyboardShortcut(.cancelAction)

				Button(NicknameColorStrings.changeColor, action: changeColor)
					.keyboardShortcut(.defaultAction)
			}
		}
		.padding(UISpacing.loose + UISpacing.tight)
		.frame(width: 390)
		.onExitCommand(perform: cancel)
	}
}
