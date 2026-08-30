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

	let content: ServerNicknameChangeContent
	let submit: () -> Void
	let cancel: () -> Void

	@FocusState private var nicknameFieldIsFocused: Bool

	var body: some View {
		VStack(spacing: 18) {
			Grid(horizontalSpacing: 8, verticalSpacing: 12) {
				GridRow {
					Text(verbatim: content.currentNicknameLabel)
						.gridColumnAlignment(.trailing)

					Text(verbatim: model.currentNickname)
						.fontWeight(.semibold)
						.textSelection(.enabled)
						.frame(width: 190, alignment: .leading)
				}

				GridRow {
					Text(verbatim: content.newNicknameLabel)

					TextField("", text: $model.proposedNickname)
						.labelsHidden()
						.focused($nicknameFieldIsFocused)
						.frame(width: 190)
						.accessibilityLabel(Text(verbatim: content.newNicknameLabel))
						.accessibilityHint(Text(verbatim: model.validationError ?? ""))
						.overlay {
							if model.validationError != nil {
								RoundedRectangle(cornerRadius: 5)
									.stroke(.red, lineWidth: 1)
									.allowsHitTesting(false)
							}
						}
						.popover(isPresented: $model.isValidationMessagePresented) {
							if let validationError = model.validationError {
								Text(verbatim: validationError)
									.padding(10)
							}
						}
				}
			}

			HStack(spacing: 8) {
				Spacer()

				Button(action: cancel) {
					Text(verbatim: content.cancelButtonTitle)
				}
				.keyboardShortcut(.cancelAction)

				Button(action: submit) {
					Text(verbatim: content.changeButtonTitle)
				}
				.keyboardShortcut(.defaultAction)
			}
		}
		.padding(20)
		.frame(width: 350, height: 131)
		.onAppear {
			nicknameFieldIsFocused = true
		}
		.onExitCommand(perform: cancel)
	}
}
