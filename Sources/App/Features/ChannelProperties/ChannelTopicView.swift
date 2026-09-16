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

	let channelName: String
	let submit: @MainActor () -> Void
	let cancel: @MainActor () -> Void

	var body: some View {
		VStack(spacing: 12) {
			Form {
				Section {
					ChannelTopicEditor(
						formattedText: $model.formattedTopic,
						accessibilityLabel: ChannelTopicStrings.headerTitle(channelName: channelName),
						submit: submit
					)
					.frame(minHeight: 94)
					.accessibilityHint(Text(verbatim: ChannelTopicStrings.editorAccessibilityHint))
				} header: {
					Text(verbatim: ChannelTopicStrings.headerTitle(channelName: channelName))
				} footer: {
					/* The count replaces the alert this sheet used to raise on
					 the keystroke that crossed the limit: the answer belongs
					 beside the text being typed, not in a dialog over it. */
					if let remaining = model.remainingLength {
						Text(verbatim: ChannelTopicStrings.lengthFooter(remaining: remaining))
							.foregroundStyle(model.fitsMaximumLength ? AnyShapeStyle(.secondary) : AnyShapeStyle(.red))
					}
				}
			}
			.formStyle(.grouped)

			HStack(spacing: 8) {
				Spacer()

				Button(action: cancel) {
					Text(verbatim: ChannelTopicStrings.cancelButtonTitle)
				}
				.keyboardShortcut(.cancelAction)

				Button(action: submit) {
					Text(verbatim: ChannelTopicStrings.changeButtonTitle)
				}
				.keyboardShortcut(.defaultAction)
				.disabled(model.fitsMaximumLength == false)
			}
		}
		.padding(20)
		.frame(minWidth: 480, idealWidth: 600, minHeight: 260, idealHeight: 280)
	}
}
