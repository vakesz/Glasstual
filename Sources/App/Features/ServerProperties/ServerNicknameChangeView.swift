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
struct ServerNicknameChangeView: View {
	@Bindable var model: ServerNicknameChangeModel

	let submit: () -> Void
	let cancel: () -> Void

	@FocusState private var nicknameFieldIsFocused: Bool

	var body: some View {
		VStack(spacing: 0) {
			VStack(alignment: .leading, spacing: 6) {
				Text(verbatim: ServerNicknameChangeStrings.changeButtonTitle)
					.font(.title2.weight(.semibold))
				Text(verbatim: ServerNicknameChangeStrings.changeDescription)
					.foregroundStyle(.secondary)
					.fixedSize(horizontal: false, vertical: true)
			}
			.frame(maxWidth: .infinity, alignment: .leading)
			.padding([.horizontal, .top], 20)
			.padding(.bottom, 12)

			Form {
				Section {
					LabeledContent(
						ServerNicknameChangeStrings.currentNicknameLabel,
						value: model.currentNickname
					)
					.textSelection(.enabled)

					LabeledContent(ServerNicknameChangeStrings.newNicknameLabel) {
						TextField(
							ServerNicknameChangeStrings.newNicknamePlaceholder,
							text: $model.proposedNickname
						)
						.labelsHidden()
						.focused($nicknameFieldIsFocused)
						.accessibilityLabel(ServerNicknameChangeStrings.newNicknameLabel)
						.onSubmit(submit)
					}

					if let message = model.validationMessage {
						ValidationMessageLabel(message)
					}
				}
			}
			.formStyle(.grouped)

			Divider()
			HStack(spacing: 8) {
				Spacer()
				Button(PromptStrings.Action.cancel, action: cancel)
					.keyboardShortcut(.cancelAction)
				Button(ServerNicknameChangeStrings.changeButtonTitle, action: submit)
					.keyboardShortcut(.defaultAction)
					.disabled(model.validationMessage != nil)
			}
			.padding(12)
		}
		.frame(minWidth: 400, idealWidth: 440, maxWidth: .infinity)
		.onAppear {
			nicknameFieldIsFocused = true
		}
	}
}
