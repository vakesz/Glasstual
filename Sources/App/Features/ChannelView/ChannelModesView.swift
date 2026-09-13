/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
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
		VStack(spacing: 12) {
			Form {
				Section {
					ForEach(ChannelMode.booleanModes, id: \.self) { mode in
						modeToggle(mode)
					}
				} header: {
					Text(verbatim: ChannelModesStrings.headingTitle(channelName: channelName))
				}

				Section {
					/* The checkbox is the row's label: the mode and the value it
					 carries are one setting, and the field is only editable
					 while the mode is on. */
					HStack(alignment: .firstTextBaseline, spacing: UISpacing.wide) {
						modeToggle(.key)
						TextField(ChannelModesStrings.channelKeyPlaceholder, text: secretKey)
							.disabled(model.isEnabled(.key) == false)
							.accessibilityLabel(Text(verbatim: ChannelMode.key.title))
							.onSubmit(submit)
					}
				} footer: {
					/* The warning replaces the alert this sheet used to raise
					 on the keystroke that crossed the limit: the answer belongs
					 beside the field being typed in, not in a dialog over it. */
					if let remaining = model.remainingKeyLength,
					   let warning = ChannelModesStrings.keyLengthWarning(remaining: remaining)
					{
						Text(verbatim: warning).foregroundStyle(.red)
					} else {
						Text(verbatim: ChannelModesStrings.channelKeyFieldHint)
					}
				}

				Section {
					HStack(alignment: .firstTextBaseline, spacing: UISpacing.wide) {
						modeToggle(.userLimit)
						TextField(ChannelModesStrings.userLimitPlaceholder, text: userLimit)
							.multilineTextAlignment(.trailing)
							.monospacedDigit()
							.frame(width: 90)
							.disabled(model.isEnabled(.userLimit) == false)
							.accessibilityLabel(Text(verbatim: ChannelMode.userLimit.title))
							.onSubmit(submit)
						Spacer()
					}
				} footer: {
					Text(verbatim: ChannelModesStrings.userLimitFieldHint)
				}
			}
			.formStyle(.grouped)

			HStack(spacing: 8) {
				Spacer()

				Button(action: cancel) {
					Text(verbatim: ChannelModesStrings.cancelButtonTitle)
				}
				.keyboardShortcut(.cancelAction)

				Button(action: submit) {
					Text(verbatim: ChannelModesStrings.changeModesButtonTitle)
				}
				.keyboardShortcut(.defaultAction)
				.disabled(model.fitsMaximumKeyLength == false)
			}
		}
		.padding(20)
		.frame(minWidth: 420, idealWidth: 460, minHeight: 440, idealHeight: 470)
	}

	private func modeToggle(_ mode: ChannelMode) -> some View {
		Toggle(isOn: modeBinding(mode)) {
			Text(verbatim: mode.title)
		}
		.toggleStyle(.checkbox)
	}
}
