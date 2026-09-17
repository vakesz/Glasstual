// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import SwiftUI

@MainActor
struct HighlightEntryView: View {
	@Bindable var model: HighlightEntryModel

	let submit: () -> Void
	let cancel: () -> Void

	@FocusState private var keywordFieldIsFocused: Bool

	var body: some View {
		VStack(spacing: 0) {
			VStack(alignment: .leading, spacing: 6) {
				Text(.HighlightEntry.windowTitle)
					.font(.title2.weight(.semibold))
				Text(.HighlightEntry.ruleDescription)
					.foregroundStyle(.secondary)
					.fixedSize(horizontal: false, vertical: true)
			}
			.frame(maxWidth: .infinity, alignment: .leading)
			.padding([.horizontal, .top], 20)
			.padding(.bottom, 12)

			Form {
				Section {
					Picker(.HighlightEntry.matchTypeLabel, selection: $model.behavior) {
						ForEach(HighlightMatchBehavior.allCases) { behavior in
							Text(behavior.title).tag(behavior)
						}
					}

					LabeledContent(.HighlightEntry.keywordLabel) {
						TextField(.HighlightEntry.keywordPlaceholder, text: $model.keyword)
							.labelsHidden()
							.focused($keywordFieldIsFocused)
							.accessibilityLabel(.HighlightEntry.keywordLabel)
							.onSubmit(submit)
					}

					if let message = model.validationMessage {
						ValidationMessageLabel(message)
					}
				} footer: {
					Text(.HighlightEntry.keywordHelp)
				}

				Section {
					Picker(.HighlightEntry.channelLabel, selection: $model.channelSelection) {
						Text(.ServerProperties.allChannels)
							.tag(HighlightChannelSelection.all)

						if model.channels.isEmpty == false {
							Divider()
						}

						ForEach(model.channels) { channel in
							Text(verbatim: channel.name)
								.tag(HighlightChannelSelection.channel(id: channel.id))
						}
					}
				} footer: {
					Text(.HighlightEntry.channelHelp)
				}
			}
			.formStyle(.grouped)

			Divider()
			HStack(spacing: 8) {
				Spacer()
				Button(PromptStrings.Action.cancel, action: cancel)
					.keyboardShortcut(.cancelAction)
				/* The rule is written back into the connection the sheet
				 belongs to, which is what saves it. */
				Button(PromptStrings.Action.confirmation, action: submit)
					.keyboardShortcut(.defaultAction)
					.disabled(model.validationMessage != nil)
			}
			.padding(12)
		}
		.frame(minWidth: 460, idealWidth: 520, maxWidth: .infinity)
		.onAppear {
			keywordFieldIsFocused = true
		}
	}
}
