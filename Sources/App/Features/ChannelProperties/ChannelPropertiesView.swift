// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import SwiftUI

@MainActor
struct ChannelPropertiesView: View {
	@Bindable var model: ChannelPropertiesModel
	let submit: () -> Void
	let cancel: () -> Void

	@FocusState private var channelNameIsFocused: Bool

	var body: some View {
		VStack(spacing: 0) {
			/* The channel this is about, named under the sheet's own title. A
			 sheet opened to create a channel has nothing to name yet. */
			SheetHeading(
				.ChannelProperties.channelPropertiesWindowTitle,
				subtitle: model.channelNameIsEditable
					? nil
					: Text(verbatim: model.config.name)
			)

			Picker(.ChannelProperties.sectionPickerLabel, selection: $model.selection) {
				ForEach(ChannelPropertiesSection.allCases) { section in
					Text(section.title)
						.tag(section)
				}
			}
			.labelsHidden()
			.pickerStyle(.segmented)
			.accessibilityLabel(.ChannelProperties.sectionPickerLabel)
			.padding(.horizontal, SheetMetrics.margin)

			switch model.selection {
			case .general: generalPane
			case .defaults: defaultsPane
			}

			/* The channel is written back into the connection that owns it,
			 which is what saves it; the confirmation says the editor is done. */
			SheetActions(
				confirmTitle: .sheetConfirmation,
				confirmIsDisabled: model.channelNameValidationMessage != nil,
				confirm: submit,
				cancel: cancel
			)
		}
		.disabled(model.isSaving)
		.frame(
			minWidth: 560,
			idealWidth: 620,
			maxWidth: .infinity,
			minHeight: 450,
			idealHeight: 500,
			maxHeight: .infinity
		)
		.onAppear { channelNameIsFocused = model.channelNameIsEditable }
		.task(id: model.secretKeyLoadGeneration) { await model.loadSecretKey() }
	}

	private var generalPane: some View {
		Form {
			Section {
				LabeledContent(.ChannelProperties.nameLabel) {
					TextField(.ChannelProperties.channelNamePlaceholder, text: $model.config.name)
						.labelsHidden()
						.disabled(model.channelNameIsEditable == false)
						.focused($channelNameIsFocused)
						.accessibilityLabel(.ChannelProperties.nameLabel)
				}
				if let message = model.channelNameValidationMessage {
					ValidationMessageLabel(message)
				}

				LabeledContent(.ChannelProperties.passwordLabel) {
					SecureField(.ChannelProperties.optional, text: $model.secretKey)
						.labelsHidden()
						.accessibilityLabel(.ChannelProperties.passwordLabel)
				}
				if let caption = model.secretKeyLengthCaption {
					if model.secretKeyIsTooLong {
						ValidationMessageLabel(caption)
					} else {
						Text(caption)
							.font(.caption)
							.foregroundStyle(.secondary)
							.monospacedDigit()
					}
				}
			} footer: {
				Text(.ChannelProperties.passwordHelp)
			}

			Section {
				LabeledContent(.ChannelProperties.labelLabel) {
					TextField(.ChannelProperties.optional, text: $model.config.label.orEmpty)
						.labelsHidden()
						.accessibilityLabel(.ChannelProperties.labelLabel)
				}
			} footer: {
				Text(.ChannelProperties.labelHelp)
			}

			Section {
				Toggle(.ChannelProperties.joinOnConnect, isOn: $model.config.autoJoin)
				Toggle(.ChannelProperties.muteThisConversation, isOn: $model.isMuted)
				Toggle(.ChannelProperties.showUnreadCountInChannelList, isOn: $model.config.showsUnreadCount)
				Toggle(
					.ChannelProperties.disableGeneralEventMessages,
					isOn: $model.config.ignoreGeneralEventMessages
				)
				Toggle(.ChannelProperties.disableHighlights, isOn: $model.config.ignoreHighlights)
				Toggle(model.inlineMediaOverrideTitle, isOn: $model.inlineMediaOverride)
			}
		}
		.formStyle(.grouped)
	}

	private var defaultsPane: some View {
		Form {
			Section {
				LabeledContent(.ChannelProperties.topicLabel) {
					TextField(.ChannelProperties.optional, text: $model.config.defaultTopic.orEmpty)
						.labelsHidden()
						.accessibilityLabel(.ChannelProperties.topicLabel)
				}
				LabeledContent(.ChannelProperties.modesLabel) {
					TextField(.ChannelProperties.optional, text: $model.config.defaultModes.orEmpty)
						.labelsHidden()
						.accessibilityLabel(.ChannelProperties.modesLabel)
				}
			} footer: {
				Text(.ChannelProperties.defaultsHelp)
			}
		}
		.formStyle(.grouped)
	}
}
