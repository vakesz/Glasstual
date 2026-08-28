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

import SwiftUI

@MainActor
struct ChannelTopicView: View {
	@Bindable var model: ChannelTopicModel

	let content: ChannelTopicContent
	let topicDidChange: @MainActor (String) -> Void
	let submit: @MainActor () -> Void
	let cancel: @MainActor () -> Void

	private var formattedTopic: Binding<String> {
		Binding(
			get: { model.formattedTopic },
			set: topicDidChange
		)
	}

	var body: some View {
		VStack(alignment: .leading, spacing: 10) {
			Text(verbatim: content.headerTitle)

			IRCFormattingTopicEditor(
				formattedText: formattedTopic,
				accessibilityLabel: content.headerTitle,
				submit: submit
			)
			.frame(height: 94)
			.accessibilityHint(Text(verbatim: content.editorAccessibilityHint))

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
		.frame(width: 600, height: 201)
		.onExitCommand(perform: cancel)
	}
}
