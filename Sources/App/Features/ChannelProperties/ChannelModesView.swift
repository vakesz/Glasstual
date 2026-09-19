// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import SwiftUI

@MainActor
struct ChannelModesView: View {
	@Bindable var model: ChannelModesModel

	let channelName: String
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
			set: model.updateSecretKey
		)
	}

	private var userLimit: Binding<String> {
		Binding(
			get: { model.userLimit },
			set: model.updateUserLimit
		)
	}

	var body: some View {
		VStack(spacing: UISpacing.wide) {
			Form {
				Section {
					ForEach(ChannelMode.booleanModes, id: \.self) { mode in
						modeToggle(mode)
					}
				} header: {
					Text(.ChannelProperties.heading(channelName))
				}

				Section {
					/* The checkbox is the row's label: the mode and the value it
					 carries are one setting, and the field is only editable
					 while the mode is on. */
					HStack(alignment: .firstTextBaseline, spacing: UISpacing.wide) {
						modeToggle(.key)
						TextField(.ChannelProperties.channelKeyPlaceholder, text: secretKey)
							.disabled(model.isEnabled(.key) == false)
							.accessibilityLabel(ChannelMode.key.title)
							.onSubmit(submit)
					}
				} footer: {
					/* The warning replaces the alert this sheet used to raise
					 on the keystroke that crossed the limit: the answer belongs
					 beside the field being typed in, not in a dialog over it. */
					if let warning = model.keyLengthCaption {
						Text(verbatim: warning).foregroundStyle(.red)
					} else {
						Text(.ChannelProperties.channelKeyFieldHint)
					}
				}

				Section {
					HStack(alignment: .firstTextBaseline, spacing: UISpacing.wide) {
						modeToggle(.userLimit)
						TextField(.ChannelProperties.userLimitPlaceholder, text: userLimit)
							.multilineTextAlignment(.trailing)
							.monospacedDigit()
							.frame(width: 90)
							.disabled(model.isEnabled(.userLimit) == false)
							.accessibilityLabel(ChannelMode.userLimit.title)
							.onSubmit(submit)
						Spacer()
					}
				} footer: {
					Text(.ChannelProperties.userLimitFieldHint)
				}
			}
			.formStyle(.grouped)

			HStack(spacing: UISpacing.regular) {
				Spacer()

				Button(PromptStrings.Action.cancel, action: cancel)
					.keyboardShortcut(.cancelAction)

				Button(.ChannelProperties.changeModesButton, action: submit)
					.keyboardShortcut(.defaultAction)
					.disabled(model.fitsKeyLengthLimit == false)
			}
		}
		.padding(SheetMetrics.margin)
		.frame(minWidth: 420, idealWidth: 460, minHeight: 440, idealHeight: 470)
	}

	private func modeToggle(_ mode: ChannelMode) -> some View {
		Toggle(mode.title, isOn: modeBinding(mode))
			.toggleStyle(.checkbox)
	}
}
