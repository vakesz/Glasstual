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
protocol ChannelPropertiesSheetDelegate: AnyObject {
	func channelPropertiesSheet(_ sender: ChannelPropertiesSheet, onOk config: ChannelConfig)
}

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

	convenience init(client: Client) {
		self.init(config: nil, onClient: client)
	}

	init(channel: Channel) {
		client = channel.associatedClient
		clientId = channel.associatedClient?.uniqueIdentifier
		self.channel = channel
		channelId = channel.uniqueIdentifier
		model = ChannelPropertiesModel(config: channel.config, client: channel.associatedClient)
		super.init(window: nil)
		installSheet()
		observeConfigurationChanges()
	}

	init(config: ChannelConfig?, onClient client: Client?) {
		self.client = client
		clientId = client?.uniqueIdentifier
		model = ChannelPropertiesModel(config: config ?? ChannelConfig(), client: client)
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
		// A nested channel editor is part of its parent server's pending edit.
		guard !(delegate is ServerPropertiesSheet) else {
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
		(delegate as? any ChannelPropertiesSheetDelegate)?.channelPropertiesSheet(self, onOk: submitted)
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
			body: ChannelPropertiesStrings.unsavedChangesWarning,
			title: ChannelPropertiesStrings.configurationChangedTitle,
			defaultButton: PromptStrings.Action.cancel,
			alternateButton: ChannelPropertiesStrings.reloadButton,
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
