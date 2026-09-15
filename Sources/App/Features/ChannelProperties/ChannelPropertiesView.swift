/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import SwiftUI

@MainActor
struct ChannelPropertiesView: View {
	@Bindable var model: ChannelPropertiesModel
	let submit: () -> Void
	let cancel: () -> Void

	@FocusState private var channelNameIsFocused: Bool

	var body: some View {
		VStack(spacing: 0) {
			heading

			Picker(ChannelPropertiesStrings.sectionPickerLabel, selection: $model.selection) {
				ForEach(ChannelPropertiesSection.allCases) { section in
					Text(verbatim: section.title)
						.tag(section)
						.disabled(section == .notifications && model.config.pushNotifications == false)
				}
			}
			.labelsHidden()
			.pickerStyle(.segmented)
			.accessibilityLabel(ChannelPropertiesStrings.sectionPickerLabel)
			.padding(.horizontal, 20)

			switch model.selection {
			case .general: generalPane
			case .defaults: defaultsPane
			case .notifications: notificationsPane
			}

			Divider()
			HStack {
				Spacer()
				Button(PromptStrings.Action.cancel, action: cancel)
					.keyboardShortcut(.cancelAction)
				/* The channel is written back into the connection that owns it,
				 which is what saves it; this one says the editor is done. */
				Button(PromptStrings.Action.confirmation, action: submit)
					.keyboardShortcut(.defaultAction)
					.disabled(model.channelNameValidationMessage != nil)
			}
			.padding(12)
		}
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
		.onChange(of: model.config.pushNotifications) { _, enabled in
			if enabled == false, model.selection == .notifications {
				model.selection = .general
			}
		}
	}

	/// The channel this is about, named under the sheet's own title. A sheet
	/// opened to create a channel has nothing to name yet.
	private var heading: some View {
		VStack(alignment: .leading, spacing: 6) {
			Text(verbatim: ChannelPropertiesStrings.heading)
				.font(.title2.weight(.semibold))
			if model.channelNameIsEditable == false {
				Text(verbatim: model.channelName)
					.foregroundStyle(.secondary)
			}
		}
		.frame(maxWidth: .infinity, alignment: .leading)
		.padding([.horizontal, .top], 20)
		.padding(.bottom, 12)
	}

	private var generalPane: some View {
		Form {
			Section {
				LabeledContent(ChannelPropertiesStrings.nameLabel) {
					TextField(ChannelPropertiesStrings.channelNamePlaceholder, text: $model.channelName)
						.labelsHidden()
						.disabled(model.channelNameIsEditable == false)
						.focused($channelNameIsFocused)
						.accessibilityLabel(ChannelPropertiesStrings.nameLabel)
				}
				if let message = model.channelNameValidationMessage {
					ValidationMessageLabel(message)
				}

				LabeledContent(ChannelPropertiesStrings.passwordLabel) {
					SecureField(ChannelPropertiesStrings.optional, text: $model.secretKey)
						.labelsHidden()
						.accessibilityLabel(ChannelPropertiesStrings.passwordLabel)
				}
				if let caption = model.secretKeyLengthCaption {
					if model.secretKeyIsTooLong {
						ValidationMessageLabel(caption)
					} else {
						Text(verbatim: caption)
							.font(.caption)
							.foregroundStyle(.secondary)
							.monospacedDigit()
					}
				}
			} footer: {
				Text(verbatim: ChannelPropertiesStrings.passwordHelp)
			}

			Section {
				LabeledContent(ChannelPropertiesStrings.labelLabel) {
					TextField(ChannelPropertiesStrings.optional, text: $model.label)
						.labelsHidden()
						.accessibilityLabel(ChannelPropertiesStrings.labelLabel)
				}
			} footer: {
				Text(verbatim: ChannelPropertiesStrings.labelHelp)
			}

			Section {
				Toggle(ChannelPropertiesStrings.joinOnConnect, isOn: $model.config.autoJoin)
				Toggle(ChannelPropertiesStrings.showNotifications, isOn: $model.config.pushNotifications)
				Toggle(ChannelPropertiesStrings.showUnreadCount, isOn: $model.config.showTreeBadgeCount)
				Toggle(
					ChannelPropertiesStrings.disableGeneralEvents,
					isOn: $model.config.ignoreGeneralEventMessages
				)
				Toggle(ChannelPropertiesStrings.disableHighlights, isOn: $model.config.ignoreHighlights)
				Toggle(model.inlineMediaOverrideTitle, isOn: $model.inlineMediaOverride)
			}
		}
		.formStyle(.grouped)
	}

	private var defaultsPane: some View {
		Form {
			Section {
				LabeledContent(ChannelPropertiesStrings.topicLabel) {
					TextField(ChannelPropertiesStrings.optional, text: $model.defaultTopic)
						.labelsHidden()
						.accessibilityLabel(ChannelPropertiesStrings.topicLabel)
				}
				LabeledContent(ChannelPropertiesStrings.modesLabel) {
					TextField(ChannelPropertiesStrings.optional, text: $model.defaultModes)
						.labelsHidden()
						.accessibilityLabel(ChannelPropertiesStrings.modesLabel)
				}
			} footer: {
				Text(verbatim: ChannelPropertiesStrings.defaultsHelp)
			}
		}
		.formStyle(.grouped)
	}

	private var notificationsPane: some View {
		Form {
			NotificationConfigurationView(model: model.notificationConfiguration)
		}
		.formStyle(.grouped)
	}
}
