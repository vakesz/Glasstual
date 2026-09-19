// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import SwiftUI

@MainActor
final class ChannelPropertiesSheet: SheetSession, ChannelScoped {
	private(set) var session: ServerSession?
	private(set) var channel: Conversation?
	private(set) var sessionId: String?
	private(set) var channelId: String?

	let model: ChannelPropertiesModel
	private let notifications = NotificationSubscriptions()
	private var saveTask: Task<Void, Never>?
	var credentialPersistence = KeychainPersistence.shared
	var settingsSaves = SettingsSaveQueue.shared

	/// What the sheet reports when the person accepts it.
	private let onSave: (ConversationConfig) -> Void
	/** Whether accepting the sheet writes the channel key to the keychain.

	 A channel editor raised from the connection sheet is part of that sheet's
	 pending edit, so the parent writes both at once when it is accepted. */
	private let savesCredentials: Bool

	init(channel: Conversation, onSave: @escaping (ConversationConfig) -> Void) {
		session = channel.associatedSession
		sessionId = channel.associatedSession?.uniqueIdentifier
		self.channel = channel
		channelId = channel.uniqueIdentifier
		model = ChannelPropertiesModel(config: channel.config, session: channel.associatedSession)
		self.onSave = onSave
		savesCredentials = true
		super.init(window: nil)
		installSheet()
		observeConfigurationChanges()
	}

	init(
		config: ConversationConfig?,
		onSession session: ServerSession?,
		savesCredentials: Bool = true,
		onSave: @escaping (ConversationConfig) -> Void
	) {
		self.session = session
		sessionId = session?.uniqueIdentifier
		model = ChannelPropertiesModel(config: config ?? ConversationConfig(), session: session)
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

	override func submit() {
		guard !model.isSaving, model.validateForSubmission() else { return }
		let submitted = model.submittedConfig
		guard savesCredentials else {
			finishSaving(submitted)
			return
		}
		model.isSaving = true
		let write = credentialPersistence.enqueue(submitted.pendingKeychainEdits, retainsFailureForTermination: false)
		saveTask = settingsSaves.submit { [self] in
			do {
				try await write.value
				let edits = submitted.pendingKeychainEdits
				var saved = submitted
				saved.acknowledgeKeychainEdits(edits)
				session?.sessionCredentials.apply(edits)
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

	private func finishSaving(_ submitted: ConversationConfig) {
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
		notifications.observe(.conversationConfigWasUpdated, object: channel) { [weak self] note in
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
		guard let channel = notification.object as? Conversation else { return }
		Alerts.alertSheet(
			title: String(localized: .ChannelProperties.thisChannelsConfigurationHasChangedDo),
			body: String(localized: .ChannelProperties.youWillLooseUnsavedChangesIf),
			defaultButton: PromptStrings.Action.cancel,
			alternateButton: String(localized: .ChannelProperties.reloadButton),
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
