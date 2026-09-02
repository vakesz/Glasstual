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
	func channelPropertiesSheetWillClose(_ sender: ChannelPropertiesSheet)
}

@objc(TDCChannelPropertiesSheet)
@MainActor
public final class ChannelPropertiesSheet: MainWindowSheetSession, ChannelScoped {
	public private(set) var client: IRCClient?
	public private(set) var channel: IRCChannel?
	public private(set) var clientId: String?
	public private(set) var channelId: String?

	let model: ChannelPropertiesModel
	private var notificationItems: [NotificationConfigurationItem] = []
	private let notifications = NotificationSubscriptions()
	private var secretKeyLengthAlertDisplayed = false

	public var config: ChannelConfig {
		get { model.config }
		set { model.replace(with: newValue) }
	}

	public convenience init(client: IRCClient) {
		self.init(config: nil, onClient: client)
	}

	public init(channel: IRCChannel) {
		client = channel.associatedClient
		clientId = channel.associatedClient?.uniqueIdentifier
		self.channel = channel
		channelId = channel.uniqueIdentifier
		model = ChannelPropertiesModel(config: channel.config)
		super.init(window: nil)
		installSheet()
		observeConfigurationChanges()
	}

	public init(config: ChannelConfig?, onClient client: IRCClient?) {
		self.client = client
		clientId = client?.uniqueIdentifier
		model = ChannelPropertiesModel(config: config ?? ChannelConfig())
		super.init(window: nil)
		installSheet()
	}

	private func installSheet() {
		notificationItems = [
			.configuration(ChannelNotificationConfiguration(eventType: .highlight, in: self)),
			.separator,
			.configuration(ChannelNotificationConfiguration(eventType: .channelMessage, in: self)),
			.configuration(ChannelNotificationConfiguration(eventType: .channelNotice, in: self)),
			.separator,
			.configuration(ChannelNotificationConfiguration(eventType: .userJoined, in: self)),
			.configuration(ChannelNotificationConfiguration(eventType: .userParted, in: self)),
		]

		let rootView = ChannelPropertiesView(
			model: model,
			notificationItems: notificationItems,
			secretKeyChanged: { [weak self] value in self?.checkSecretKeyLength(value) },
			submit: { [weak self] in self?.ok(nil) },
			cancel: { [weak self] in self?.cancel(nil) }
		)
		/* `ChannelPropertiesView` owns the size; a second frame here would only
		 fight it. */
		setContent(rootView)
	}

	public func start() {
		startSheet()
	}

	override public func ok(_ sender: Any?) {
		guard model.validateForSubmission() else { return }
		removeConfigurationObserver()
		model.config = model.submittedConfig
		(delegate as? any ChannelPropertiesSheetDelegate)?.channelPropertiesSheet(self, onOk: model.config)
		super.ok(sender)
	}

	override public func cancel(_ sender: Any?) {
		removeConfigurationObserver()
		super.cancel(sender)
	}

	private func checkSecretKeyLength(_ value: String) {
		guard let client else { return }
		let maximum = client.supportInfo.maximumKeyLength
		guard maximum > 0, value.count > maximum, secretKeyLengthAlertDisplayed == false else { return }
		secretKeyLengthAlertDisplayed = true
		Alerts.alert(
			withMessage: ChannelValidationStrings.maximumKeyLengthMessage,
			title: ChannelValidationStrings.maximumKeyLengthTitle(
				networkName: client.networkNameAlt,
				maximumLength: Int(clamping: maximum)
			),
			defaultButton: PromptStrings.Action.confirmation,
			alternateButton: nil,
			otherButton: nil,
			suppressionKey: ChannelValidationSuppressionKey.maximumSecretKeyLength.rawValue,
			suppressionText: nil,
			completionBlock: nil
		)
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

	private func underlyingConfigurationChanged(_ notification: Notification) {
		guard let channel = notification.object as? IRCChannel else { return }
		Alerts.alert(
			withMessage: ChannelPropertiesStrings.unsavedChangesWarning,
			title: ChannelPropertiesStrings.configurationChangedTitle,
			defaultButton: PromptStrings.Action.yes,
			alternateButton: PromptStrings.Action.no,
			otherButton: nil
		) { [weak self] outcome in
			guard let self, outcome.response == .default else { return }
			model.replace(with: channel.config)
		}
	}

	override public func sheetDidEnd(withReturnCode _: Int) {
		removeConfigurationObserver()
		(delegate as? any ChannelPropertiesSheetDelegate)?.channelPropertiesSheetWillClose(self)
	}
}
