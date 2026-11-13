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

			TabView(selection: $model.selection) {
				ForEach(ChannelPropertiesSection.allCases) { section in
					pane(section)
						.tabItem { Text(section.title) }
						.tag(section)
				}
			}
			.padding(.horizontal, SheetMetrics.margin)
			.padding(.top, UISpacing.regular)

			SheetActions(
				confirmTitle: Text(PromptStrings.Action.save),
				confirmIsDisabled: model.channelNameValidationMessage != nil,
				confirm: submit,
				cancel: cancel
			)
		}
		.disabled(model.isSaving)
		.interactiveDismissDisabled(model.isSaving)
		.sheetFrame(.regular, minHeight: 480, idealHeight: 540)
		.onAppear { channelNameIsFocused = model.channelNameIsEditable }
		.task(id: model.secretKeyLoadGeneration) { await model.loadSecretKey() }
	}

	@ViewBuilder
	private func pane(_ section: ChannelPropertiesSection) -> some View {
		switch section {
		case .general: generalPane
		case .defaults: defaultsPane
		}
	}

	private var generalPane: some View {
		Form {
			Section {
				TextField(
					String(localized: .ChannelProperties.nameLabel),
					text: $model.config.name,
					prompt: Text(.ChannelProperties.channelNamePlaceholder)
				)
				.disabled(model.channelNameIsEditable == false)
				.focused($channelNameIsFocused)
				if let message = model.channelNameValidationMessage {
					ValidationMessageLabel(message)
				}

				SecureField(
					String(localized: .ChannelProperties.passwordLabel),
					text: $model.secretKey,
					prompt: Text(.ChannelProperties.optional)
				)
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
				TextField(
					String(localized: .ChannelProperties.labelLabel),
					text: $model.config.label.orEmpty,
					prompt: Text(.ChannelProperties.optional)
				)
			} footer: {
				Text(.ChannelProperties.labelHelp)
			}

			Section {
				Toggle(.ChannelProperties.joinOnConnect, isOn: $model.config.autoJoin)
				Toggle(.ChannelProperties.muteThisConversation, isOn: $model.isMuted)
				Toggle(.ChannelProperties.showUnreadCountInChannelList, isOn: $model.config.showsUnreadCount)
				Picker(.ChannelProperties.generalEventMessages, selection: $model.config.generalEventMessageDisplay) {
					Text(.ChannelProperties.generalEventMessagesShow).tag(GeneralEventMessageDisplay.show)
					Text(.ChannelProperties.generalEventMessagesCollapse).tag(GeneralEventMessageDisplay.collapse)
					Text(.ChannelProperties.generalEventMessagesHide).tag(GeneralEventMessageDisplay.hide)
				}
				.help(.ChannelProperties.generalEventMessagesHelp)
				Toggle(.ChannelProperties.disableHighlights, isOn: $model.config.ignoreHighlights)
				Toggle(model.inlineMediaOverrideTitle, isOn: $model.inlineMediaOverride)
			}

			if let profile = model.serverProfile {
				Section {
					if let displayName = profile.displayName {
						LabeledContent(.ChannelProperties.displayNameRow) {
							Text(TranscriptIsolate.isolated(displayName.text))
								.textSelection(.enabled)
						}
					}
					if let avatar = profile.avatar {
						LabeledContent(.ChannelProperties.pictureRow) {
							Text(avatar.template)
								.lineLimit(2)
								.truncationMode(.middle)
								.textSelection(.enabled)
						}
					}
				} header: {
					Text(.ChannelProperties.serverProfileSection)
				}
			}
		}
		.formStyle(.grouped)
	}

	private var defaultsPane: some View {
		Form {
			Section {
				TextField(
					String(localized: .ChannelProperties.topicLabel),
					text: $model.config.defaultTopic.orEmpty,
					prompt: Text(.ChannelProperties.optional)
				)
				TextField(
					String(localized: .ChannelProperties.modesLabel),
					text: $model.config.defaultModes.orEmpty,
					prompt: Text(.ChannelProperties.optional)
				)
			} footer: {
				Text(.ChannelProperties.defaultsHelp)
			}
		}
		.formStyle(.grouped)
	}
}
