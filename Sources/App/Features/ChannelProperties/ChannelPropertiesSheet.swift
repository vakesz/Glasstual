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
public protocol ChannelPropertiesSheetDelegate: AnyObject {
	func channelPropertiesSheet(_ sender: ChannelPropertiesSheet, onOk config: ChannelConfig)
}

@MainActor
public final class ChannelPropertiesSheet: MainWindowSheetSession, ChannelScoped {
	public private(set) var client: IRCClient?
	public private(set) var channel: Channel?
	public private(set) var clientId: String?
	public private(set) var channelId: String?

	let model: ChannelPropertiesModel
	private let notifications = NotificationSubscriptions()

	public convenience init(client: IRCClient) {
		self.init(config: nil, onClient: client)
	}

	public init(channel: Channel) {
		client = channel.associatedClient
		clientId = channel.associatedClient?.uniqueIdentifier
		self.channel = channel
		channelId = channel.uniqueIdentifier
		model = ChannelPropertiesModel(config: channel.config, client: channel.associatedClient)
		super.init(window: nil)
		installSheet()
		observeConfigurationChanges()
	}

	public init(config: ChannelConfig?, onClient client: IRCClient?) {
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

	public func start() {
		startSheet()
	}

	override public func submit() {
		guard model.validateForSubmission() else { return }
		removeConfigurationObserver()
		model.config = model.submittedConfig
		(delegate as? any ChannelPropertiesSheetDelegate)?.channelPropertiesSheet(self, onOk: model.config)
		super.submit()
	}

	override public func cancel() {
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

	override public func sheetDidEnd() {
		removeConfigurationObserver()
	}
}
