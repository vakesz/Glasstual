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

import AppKit
import SwiftUI

@MainActor
struct NicknameColorView: View {
	@Bindable var model: NicknameColorModel

	let content: NicknameColorContent
	let selectColor: @MainActor @Sendable (NSColor) -> Void
	let setUsesDefaultColor: @MainActor @Sendable (Bool) -> Void
	let save: @MainActor @Sendable () -> Void
	let cancel: @MainActor @Sendable () -> Void

	private var selectedColor: Binding<Color> {
		Binding(
			get: { Color(nsColor: model.selectedColor) },
			set: { selectColor(NSColor($0)) }
		)
	}

	private var usesDefaultColor: Binding<Bool> {
		Binding(
			get: { model.usesDefaultColor },
			set: setUsesDefaultColor
		)
	}

	var body: some View {
		VStack(spacing: 18) {
			HStack(spacing: 12) {
				ColorPicker(content.colorPickerLabel, selection: selectedColor)
					.disabled(model.usesDefaultColor)
					.accessibilityHint(Text(verbatim: content.colorPickerAccessibilityHint))

				Toggle(isOn: usesDefaultColor) {
					Text(verbatim: content.useDefaultColorTitle)
				}
				.accessibilityHint(Text(verbatim: content.useDefaultColorAccessibilityHint))
			}

			HStack(spacing: 8) {
				Spacer()

				Button(action: cancel) {
					Text(verbatim: content.cancelButtonTitle)
				}
				.keyboardShortcut(.cancelAction)

				Button(action: save) {
					Text(verbatim: content.saveButtonTitle)
				}
				.keyboardShortcut(.defaultAction)
			}
		}
		.padding(20)
		.frame(width: 390, height: 112)
		.onExitCommand(perform: cancel)
	}
}
