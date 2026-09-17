// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import SwiftUI

@MainActor
final class ChannelPropertiesSheet: SheetSession, ChannelScoped {
	private(set) var client: Client?
	private(set) var channel: Channel?
	private(set) var clientId: String?
	private(set) var channelId: String?

	let model: ChannelPropertiesModel
	private let notifications = NotificationSubscriptions()
	private var saveTask: Task<Void, Never>?
	var credentialPersistence = KeychainPersistence.shared

	/// What the sheet reports when the person accepts it.
	private let onSave: (ChannelConfig) -> Void
	/** Whether accepting the sheet writes the channel key to the keychain.

	 A channel editor raised from the connection sheet is part of that sheet's
	 pending edit, so the parent writes both at once when it is accepted. */
	private let savesCredentials: Bool

	init(channel: Channel, onSave: @escaping (ChannelConfig) -> Void) {
		client = channel.associatedClient
		clientId = channel.associatedClient?.uniqueIdentifier
		self.channel = channel
		channelId = channel.uniqueIdentifier
		model = ChannelPropertiesModel(config: channel.config, client: channel.associatedClient)
		self.onSave = onSave
		savesCredentials = true
		super.init(window: nil)
		installSheet()
		observeConfigurationChanges()
	}

	init(
		config: ChannelConfig?,
		onClient client: Client?,
		savesCredentials: Bool = true,
		onSave: @escaping (ChannelConfig) -> Void
	) {
		self.client = client
		clientId = client?.uniqueIdentifier
		model = ChannelPropertiesModel(config: config ?? ChannelConfig(), client: client)
		self.onSave = onSave
		self.savesCredentials = savesCredentials
		super.init(window: nil)
		installSheet()
	}

	private func installSheet() {
		let rootView = ChannelPropertiesView(
			model: model,
			submit: { [weak self] in self?.submit() },
			cancel: { [weak self] in self?.cancel() }
		)
		setContent(rootView)
	}

	func start() {
		startSheet()
	}

	override func submit() {
		guard !model.isSaving, model.validateForSubmission() else { return }
		let submitted = model.submittedConfig
		guard savesCredentials else {
			finishSaving(submitted)
			return
		}
		model.isSaving = true
		let write = credentialPersistence.enqueue(submitted.pendingKeychainEdits, retainsFailureForTermination: false)
		saveTask = credentialPersistence.submitSettingsSave { [self] in
			do {
				try await write.value
				let edits = submitted.pendingKeychainEdits
				var saved = submitted
				saved.acknowledgeKeychainEdits(edits)
				client?.sessionCredentials.apply(edits)
				finishSaving(saved)
				return true
			} catch {
				model.isSaving = false
				saveTask = nil
				KeychainAlerts.showFailure(error)
				return false
			}
		}
	}

	private func finishSaving(_ submitted: ChannelConfig) {
		saveTask = nil
		model.isSaving = false
		removeConfigurationObserver()
		model.config = submitted
		onSave(submitted)
		super.submit()
	}

	override func cancel() {
		guard !model.isSaving else { return }
		saveTask?.cancel()
		saveTask = nil
		model.isSaving = false
		removeConfigurationObserver()
		super.cancel()
	}

	private func observeConfigurationChanges() {
		guard let channel else { return }
		notifications.observe(.ircChannelConfigurationWasUpdated, object: channel) { [weak self] note in
			self?.underlyingConfigurationChanged(note)
		}
	}

	private func removeConfigurationObserver() {
		notifications.cancelAll()
	}

	/** The channel was reconfigured from somewhere else while the sheet is open.

	 The alert is a sheet on the window this sheet is already on, so it arrives
	 over the edits it is asking about rather than on whatever window happened
	 to be visible. Keeping what is typed is the default; reloading is the
	 destructive answer, because it throws those edits away. */
	private func underlyingConfigurationChanged(_ notification: Notification) {
		guard let channel = notification.object as? Channel else { return }
		Alerts.alertSheet(
			body: String(localized: .ChannelProperties.youWillLooseUnsavedChangesIf),
			title: String(localized: .ChannelProperties.thisChannelsConfigurationHasChangedDo),
			defaultButton: PromptStrings.Action.cancel,
			alternateButton: String(localized: .ChannelProperties.reloadButton),
			otherButton: nil,
			destructiveButton: .alternate
		) { [weak self] outcome in
			guard let self, outcome.response == .alternate else { return }
			model.replace(with: channel.config)
		}
	}

	override func sheetDidEnd() {
		removeConfigurationObserver()
	}
}

@MainActor
struct ChannelPropertiesView: View {
	@Bindable var model: ChannelPropertiesModel
	let submit: () -> Void
	let cancel: () -> Void

	@FocusState private var channelNameIsFocused: Bool

	var body: some View {
		VStack(spacing: 0) {
			heading

			Picker(.ChannelProperties.sectionPickerLabel, selection: $model.selection) {
				ForEach(ChannelPropertiesSection.allCases) { section in
					Text(section.title)
						.tag(section)
				}
			}
			.labelsHidden()
			.pickerStyle(.segmented)
			.accessibilityLabel(.ChannelProperties.sectionPickerLabel)
			.padding(.horizontal, 20)

			switch model.selection {
			case .general: generalPane
			case .defaults: defaultsPane
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

	/// The channel this is about, named under the sheet's own title. A sheet
	/// opened to create a channel has nothing to name yet.
	private var heading: some View {
		VStack(alignment: .leading, spacing: 6) {
			Text(.ChannelProperties.channelPropertiesWindowTitle)
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
				LabeledContent(.ChannelProperties.nameLabel) {
					TextField(.ChannelProperties.channelNamePlaceholder, text: $model.channelName)
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
					TextField(.ChannelProperties.optional, text: $model.label)
						.labelsHidden()
						.accessibilityLabel(.ChannelProperties.labelLabel)
				}
			} footer: {
				Text(.ChannelProperties.labelHelp)
			}

			Section {
				Toggle(.ChannelProperties.joinOnConnect, isOn: $model.config.autoJoin)
				Toggle(.ChannelProperties.muteThisConversation, isOn: $model.isMuted)
				Toggle(.ChannelProperties.showUnreadCountInChannelList, isOn: $model.config.showTreeBadgeCount)
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
					TextField(.ChannelProperties.optional, text: $model.defaultTopic)
						.labelsHidden()
						.accessibilityLabel(.ChannelProperties.topicLabel)
				}
				LabeledContent(.ChannelProperties.modesLabel) {
					TextField(.ChannelProperties.optional, text: $model.defaultModes)
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
