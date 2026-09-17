// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import SwiftUI

@MainActor
struct ChannelTopicView: View {
	@Bindable var model: ChannelTopicModel

	let channelName: String
	let submit: @MainActor () -> Void
	let cancel: @MainActor () -> Void

	var body: some View {
		VStack(spacing: 12) {
			Form {
				Section {
					ChannelTopicEditor(
						formattedText: $model.formattedTopic,
						accessibilityLabel: String(localized: .ChannelTopic.topicLabel(channelName)),
						submit: submit
					)
					.frame(minHeight: 94)
					.accessibilityHint(.ChannelTopic.editorAccessibilityHint)
				} header: {
					Text(.ChannelTopic.topicLabel(channelName))
				} footer: {
					/* The count replaces the alert this sheet used to raise on
					 the keystroke that crossed the limit: the answer belongs
					 beside the text being typed, not in a dialog over it. */
					if let remaining = model.remainingLength {
						Text(verbatim: ChannelTopicModel.lengthFooter(remaining: remaining))
							.foregroundStyle(model.fitsMaximumLength ? AnyShapeStyle(.secondary) : AnyShapeStyle(.red))
					}
				}
			}
			.formStyle(.grouped)

			HStack(spacing: 8) {
				Spacer()

				Button(.ChannelTopic.cancelButton, action: cancel)
					.keyboardShortcut(.cancelAction)

				Button(.ChannelTopic.changeTopicButton, action: submit)
					.keyboardShortcut(.defaultAction)
					.disabled(model.fitsMaximumLength == false)
			}
		}
		.padding(20)
		.frame(minWidth: 480, idealWidth: 600, minHeight: 260, idealHeight: 280)
	}
}
