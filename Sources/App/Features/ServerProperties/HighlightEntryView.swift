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
struct HighlightEntryView: View {
	@Bindable var model: HighlightEntryModel

	let submit: () -> Void
	let cancel: () -> Void

	@FocusState private var keywordFieldIsFocused: Bool

	var body: some View {
		VStack(spacing: 0) {
			VStack(alignment: .leading, spacing: 6) {
				Text(verbatim: HighlightEntryStrings.windowTitle)
					.font(.title2.weight(.semibold))
				Text(verbatim: HighlightEntryStrings.ruleDescription)
					.foregroundStyle(.secondary)
					.fixedSize(horizontal: false, vertical: true)
			}
			.frame(maxWidth: .infinity, alignment: .leading)
			.padding([.horizontal, .top], 20)
			.padding(.bottom, 12)

			Form {
				Section {
					Picker(HighlightEntryStrings.matchTypeLabel, selection: $model.behavior) {
						ForEach(HighlightMatchBehavior.allCases) { behavior in
							Text(verbatim: ServerPropertiesStrings.Highlight.matchType(
								isExcluded: behavior.excludesMatches
							))
							.tag(behavior)
						}
					}

					LabeledContent(HighlightEntryStrings.keywordLabel) {
						TextField(HighlightEntryStrings.keywordPlaceholder, text: $model.keyword)
							.labelsHidden()
							.focused($keywordFieldIsFocused)
							.accessibilityLabel(HighlightEntryStrings.keywordLabel)
							.onSubmit(submit)
					}

					if let message = model.validationMessage {
						ValidationMessageLabel(message)
					}
				} footer: {
					Text(verbatim: HighlightEntryStrings.keywordHelp)
				}

				Section {
					Picker(HighlightEntryStrings.channelLabel, selection: $model.channelSelection) {
						Text(verbatim: ServerPropertiesStrings.Highlight.allChannels)
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
					Text(verbatim: HighlightEntryStrings.channelHelp)
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
