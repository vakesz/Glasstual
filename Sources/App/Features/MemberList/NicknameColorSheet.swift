// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
import Observation
import SwiftUI

@MainActor
@Observable
final class NicknameColorModel {
	static let initialPickerColor = NSColor(
		calibratedRed: 0.058_130_498_98,
		green: 0.055_541_899_06,
		blue: 1,
		alpha: 1
	)

	let nickname: String
	private(set) var selectedColor: NSColor
	private(set) var usesDefaultColor: Bool

	init(nickname: String, overrideColor: NSColor?) {
		self.nickname = nickname
		selectedColor = overrideColor ?? Self.initialPickerColor
		usesDefaultColor = overrideColor == nil
	}

	var colorForPersistence: NSColor? {
		usesDefaultColor ? nil : selectedColor
	}

	/// The colour the transcript would draw the nickname in, as the sheet
	/// stands: what was chosen, or the colour the nickname hashes to when the
	/// sheet is offering to pin nothing.
	var previewColor: NSColor {
		usesDefaultColor
			? NicknameColors.generatedColor(for: nickname)
			: selectedColor
	}

	func setUsesDefaultColor(_ usesDefaultColor: Bool) {
		self.usesDefaultColor = usesDefaultColor

		/* The system colour panel is shared and modeless. Left open over a
		 picker that is now disabled it goes on offering colours to nothing. */
		if usesDefaultColor, NSColorPanel.sharedColorPanelExists {
			NSColorPanel.shared.close()
		}
	}

	func selectColor(_ color: NSColor) {
		selectedColor = color
		usesDefaultColor = false
	}
}

@MainActor
final class NicknameColorSheet: SheetSession {
	let model: NicknameColorModel

	private let nickname: String
	/// Run once the override has been stored, so the caller can redraw whatever
	/// draws a nickname in it.
	private let onColorChange: () -> Void

	init(nickname: String, onColorChange: @escaping () -> Void) {
		self.nickname = nickname
		self.onColorChange = onColorChange
		model = NicknameColorModel(
			nickname: nickname,
			overrideColor: NicknameColors.pinnedColor(for: nickname)
		)

		super.init(window: nil)
		installSheet()
	}

	private func installSheet() {
		setContent(NicknameColorView(
			model: model,
			changeColor: { [weak self] in self?.submit() },
			cancel: { [weak self] in self?.cancel() }
		))
	}

	func start() {
		startSheet()
	}

	override func submit() {
		NicknameColors.setOverride(model.colorForPersistence, for: nickname)

		onColorChange()

		super.submit()
	}
}

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
			Text(.MemberList.windowTitle(model.nickname))
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
				.accessibilityLabel(.MemberList.previewAccessibilityLabel(model.nickname))

			HStack(spacing: UISpacing.wide) {
				ColorPicker(.MemberList.colorPickerLabel, selection: selectedColor)
					.disabled(model.usesDefaultColor)
					.accessibilityHint(.MemberList.colorPickerAccessibilityHint)

				Toggle(.MemberList.useDefaultColor, isOn: usesDefaultColor)
					.accessibilityHint(.MemberList.useDefaultColorAccessibilityHint)
			}

			HStack(spacing: UISpacing.regular) {
				Spacer()

				Button(PromptStrings.Action.cancel, action: cancel)
					.keyboardShortcut(.cancelAction)

				Button(.MemberList.changeColor, action: changeColor)
					.keyboardShortcut(.defaultAction)
			}
		}
		.padding(UISpacing.loose + UISpacing.tight)
		.frame(width: 390)
		.onExitCommand(perform: cancel)
	}
}
