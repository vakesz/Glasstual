/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import SwiftUI

@MainActor
struct ChannelPropertiesView: View {
	@Bindable var model: ChannelPropertiesModel
	let notificationItems: [NotificationConfigurationItem]
	let secretKeyChanged: (String) -> Void
	let submit: () -> Void
	let cancel: () -> Void

	@FocusState private var channelNameIsFocused: Bool

	var body: some View {
		VStack(spacing: 12) {
			Picker("", selection: $model.selection) {
				ForEach(ChannelPropertiesSection.allCases) { section in
					Text(verbatim: section.title)
						.tag(section)
						.disabled(section == .notifications && model.config.pushNotifications == false)
				}
			}
			.labelsHidden()
			.pickerStyle(.segmented)

			Group {
				switch model.selection {
				case .general: generalPane
				case .defaults: defaultsPane
				case .notifications: notificationsPane
				}
			}
			.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

			HStack(spacing: 8) {
				Spacer()
				Button(PromptStrings.Action.cancel, action: cancel)
					.keyboardShortcut(.cancelAction)
				Button(PromptStrings.Action.save, action: submit)
					.keyboardShortcut(.defaultAction)
			}
		}
		.padding(20)
		.frame(minWidth: 520, minHeight: 390)
		.onAppear { channelNameIsFocused = model.channelNameIsEditable }
		.onExitCommand(perform: cancel)
		.onChange(of: model.config.pushNotifications) { _, enabled in
			if enabled == false, model.selection == .notifications {
				model.selection = .general
			}
		}
	}

	private var generalPane: some View {
		Form {
			LabeledContent(ChannelPropertiesStrings.nameLabel) {
				TextField("#example", text: $model.channelName)
					.labelsHidden()
					.disabled(model.channelNameIsEditable == false)
					.focused($channelNameIsFocused)
					.accessibilityLabel(ChannelPropertiesStrings.nameLabel)
					.overlay {
						if model.channelNameValidationError != nil {
							RoundedRectangle(cornerRadius: 5).stroke(.red, lineWidth: 1)
						}
					}
					.popover(isPresented: $model.isValidationMessagePresented) {
						if let error = model.channelNameValidationError {
							Text(verbatim: error).padding(10)
						}
					}
			}
			LabeledContent(ChannelPropertiesStrings.passwordLabel) {
				SecureField(ChannelPropertiesStrings.optional, text: $model.secretKey)
					.labelsHidden()
					.accessibilityLabel(ChannelPropertiesStrings.passwordLabel)
					.onChange(of: model.secretKey) { _, value in secretKeyChanged(value) }
			}
			LabeledContent(ChannelPropertiesStrings.labelLabel) {
				TextField(ChannelPropertiesStrings.optional, text: $model.label)
					.labelsHidden()
					.accessibilityLabel(ChannelPropertiesStrings.labelLabel)
			}
			Text(verbatim: ChannelPropertiesStrings.labelHelp)
				.font(.caption)
				.foregroundStyle(.secondary)

			Toggle(ChannelPropertiesStrings.joinOnConnect, isOn: $model.config.autoJoin)
			Toggle(ChannelPropertiesStrings.showNotifications, isOn: $model.config.pushNotifications)
			Toggle(ChannelPropertiesStrings.showUnreadCount, isOn: $model.config.showTreeBadgeCount)
			Toggle(ChannelPropertiesStrings.disableGeneralEvents, isOn: $model.config.ignoreGeneralEventMessages)
			Toggle(ChannelPropertiesStrings.disableHighlights, isOn: $model.config.ignoreHighlights)
			Toggle(ChannelPropertiesStrings.disableInlineMedia, isOn: $model.config.inlineMediaDisabled)
			Toggle(ChannelPropertiesStrings.showInlineMedia, isOn: $model.config.inlineMediaEnabled)
		}
		.formStyle(.grouped)
	}

	private var defaultsPane: some View {
		Form {
			Text(verbatim: ChannelPropertiesStrings.defaultsHelp)
			LabeledContent(ChannelPropertiesStrings.topicLabel) {
				TextField(ChannelPropertiesStrings.optional, text: $model.defaultTopic)
					.labelsHidden()
			}
			LabeledContent(ChannelPropertiesStrings.modesLabel) {
				TextField(ChannelPropertiesStrings.optional, text: $model.defaultModes)
					.labelsHidden()
			}
		}
		.formStyle(.grouped)
	}

	private var notificationsPane: some View {
		Form {
			NotificationConfigurationView(
				notifications: notificationItems,
				allowsInheritedState: true
			)
		}
		.formStyle(.grouped)
	}
}
