/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \\ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\\___/_/\\_\\__|\\__,_|\\__,_|_|
 *
 * Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 *********************************************************************** */

import SwiftUI

@MainActor
struct ChannelModesView: View {
	@Bindable var model: ChannelModesModel
	@FocusState private var saveButtonIsFocused: Bool

	let content: ChannelModesContent
	let secretKeyDidChange: @MainActor (String) -> Void
	let userLimitDidChange: @MainActor (String) -> Void
	let submit: @MainActor () -> Void
	let cancel: @MainActor () -> Void

	private func modeBinding(_ mode: ChannelMode) -> Binding<Bool> {
		Binding(
			get: { model.isEnabled(mode) },
			set: { model.setMode(mode, enabled: $0) }
		)
	}

	private var secretKey: Binding<String> {
		Binding(
			get: { model.secretKey },
			set: secretKeyDidChange
		)
	}

	private var userLimit: Binding<String> {
		Binding(
			get: { model.userLimit },
			set: userLimitDidChange
		)
	}

	var body: some View {
		VStack(alignment: .leading, spacing: 16) {
			Text(verbatim: content.headingTitle)
				.font(.headline)
				.textSelection(.enabled)
				.accessibilityAddTraits(.isHeader)

			VStack(alignment: .leading, spacing: 10) {
				ForEach(ChannelMode.booleanModes, id: \.self) { mode in
					modeToggle(mode)
				}
			}

			Divider()

			VStack(alignment: .leading, spacing: 12) {
				HStack(alignment: .firstTextBaseline, spacing: 12) {
					modeToggle(.key)
					TextField("", text: secretKey)
						.textFieldStyle(.roundedBorder)
						.disabled(model.isEnabled(.key) == false)
						.accessibilityLabel(Text(verbatim: content.title(for: .key)))
						.accessibilityHint(Text(verbatim: content.channelKeyFieldHint))
						.onSubmit(submit)
				}

				HStack(alignment: .firstTextBaseline, spacing: 12) {
					modeToggle(.userLimit)
					TextField("", text: userLimit)
						.textFieldStyle(.roundedBorder)
						.multilineTextAlignment(.trailing)
						.monospacedDigit()
						.frame(width: 80)
						.disabled(model.isEnabled(.userLimit) == false)
						.accessibilityLabel(Text(verbatim: content.title(for: .userLimit)))
						.accessibilityHint(Text(verbatim: content.userLimitFieldHint))
						.onSubmit(submit)

					Spacer()
				}
			}

			HStack(spacing: 8) {
				Spacer()

				Button(action: cancel) {
					Text(verbatim: content.cancelButtonTitle)
				}
				.keyboardShortcut(.cancelAction)

				Button(action: submit) {
					Text(verbatim: content.saveButtonTitle)
				}
				.keyboardShortcut(.defaultAction)
				.focused($saveButtonIsFocused)
			}
		}
		.padding(20)
		.frame(width: 440, height: 390)
		.onAppear {
			saveButtonIsFocused = true
		}
		.onExitCommand(perform: cancel)
	}

	private func modeToggle(_ mode: ChannelMode) -> some View {
		Toggle(isOn: modeBinding(mode)) {
			Text(verbatim: content.title(for: mode))
		}
		.toggleStyle(.checkbox)
		.keyboardShortcut(KeyEquivalent(Character(mode.rawValue)), modifiers: [])
	}
}
