// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
import Observation
import SwiftUI

@MainActor
struct HighlightRuleView: View {
	@Bindable var model: HighlightRuleModel

	let submit: () -> Void
	let cancel: () -> Void

	@FocusState private var keywordFieldIsFocused: Bool

	var body: some View {
		VStack(spacing: 0) {
			SheetHeading(.ServerProperties.highlightRuleWindowTitle, subtitle: Text(.ServerProperties.ruleDescription))

			Form {
				Section {
					Picker(.ServerProperties.matchTypeLabel, selection: $model.behavior) {
						ForEach(HighlightMatchBehavior.allCases) { behavior in
							Text(behavior.title).tag(behavior)
						}
					}

					LabeledContent(.ServerProperties.keywordLabel) {
						TextField(.ServerProperties.keywordPlaceholder, text: $model.keyword)
							.labelsHidden()
							.focused($keywordFieldIsFocused)
							.accessibilityLabel(.ServerProperties.keywordLabel)
							.onSubmit(submit)
					}

					if let message = model.validationMessage {
						ValidationMessageLabel(message)
					}
				} footer: {
					Text(.ServerProperties.keywordHelp)
				}

				Section {
					Picker(.ServerProperties.channelLabel, selection: $model.channelSelection) {
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
					Text(.ServerProperties.channelHelp)
				}
			}
			.formStyle(.grouped)

			/* The rule is written back into the connection the sheet belongs to,
			 which is what saves it. */
			SheetActions(
				confirmTitle: .sheetConfirmation,
				confirmIsDisabled: model.validationMessage != nil,
				confirm: submit,
				cancel: cancel
			)
		}
		.sheetFrame(.regular)
		.onAppear {
			keywordFieldIsFocused = true
		}
	}
}
