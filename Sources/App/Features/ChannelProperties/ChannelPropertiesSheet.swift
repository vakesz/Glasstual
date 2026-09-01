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

import AppKit
import SwiftUI

@MainActor
public protocol ChannelPropertiesSheetDelegate: AnyObject {
	func channelPropertiesSheet(_ sender: ChannelPropertiesSheet, onOk config: ChannelConfig)
	func channelPropertiesSheetWillClose(_ sender: ChannelPropertiesSheet)
}

@objc(TDCChannelPropertiesSheet)
@MainActor
public final class ChannelPropertiesSheet: SheetBase, NSWindowDelegate, TDCChannelPrototype {
	private static let contentSize = NSSize(width: 560, height: 450)

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

	public convenience init(clientId: String) {
		self.init(config: nil, onClientWithId: clientId)
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

	public convenience init(config: ChannelConfig?) {
		self.init(config: config, onClientWithId: nil)
	}

	public init(config: ChannelConfig?, onClient client: IRCClient?) {
		self.client = client
		clientId = client?.uniqueIdentifier
		model = ChannelPropertiesModel(config: config ?? ChannelConfig())
		super.init(window: nil)
		installSheet()
	}

	public convenience init(config: ChannelConfig?, onClientWithId clientId: String?) {
		self.init(config: config, onClient: nil)
		self.clientId = clientId
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
		let hostedSheet = NSWindow(
			contentRect: NSRect(origin: .zero, size: Self.contentSize),
			styleMask: [.titled, .resizable, .fullSizeContentView],
			backing: .buffered,
			defer: false
		)
		hostedSheet.contentViewController = NSHostingController(rootView: rootView)
		hostedSheet.contentMinSize = Self.contentSize
		hostedSheet.delegate = self
		hostedSheet.isReleasedWhenClosed = false
		hostedSheet.isRestorable = false
		hostedSheet.tabbingMode = .disallowed
		hostedSheet.preventsApplicationTerminationWhenModal = false
		hostedSheet.autorecalculatesKeyViewLoop = true
		hostedSheet.title = ChannelPropertiesStrings.windowTitle
		hostedSheet.titleVisibility = .hidden
		hostedSheet.titlebarAppearsTransparent = true
		hostedSheet.titlebarSeparatorStyle = .none
		sheet = hostedSheet
	}

	public func start() {
		startSheet()
	}

	@IBAction override public func ok(_ sender: Any?) {
		guard model.validateForSubmission() else { return }
		removeConfigurationObserver()
		model.config = model.submittedConfig
		(delegate as? any ChannelPropertiesSheetDelegate)?.channelPropertiesSheet(self, onOk: model.config)
		super.ok(sender)
	}

	@IBAction override public func cancel(_ sender: Any?) {
		removeConfigurationObserver()
		super.cancel(sender)
	}

	private func checkSecretKeyLength(_ value: String) {
		guard let client else { return }
		let maximum = client.supportInfo.maximumKeyLength
		guard maximum > 0, value.count > maximum, secretKeyLengthAlertDisplayed == false else { return }
		secretKeyLengthAlertDisplayed = true
		TDCAlert.alertSheet(
			with: sheet,
			body: ChannelValidationStrings.maximumKeyLengthMessage,
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
		TDCAlert.alertSheet(
			with: sheet,
			body: ChannelPropertiesStrings.unsavedChangesWarning,
			title: ChannelPropertiesStrings.configurationChangedTitle,
			defaultButton: PromptStrings.Action.yes,
			alternateButton: PromptStrings.Action.no,
			otherButton: nil
		) { [weak self] outcome in
			guard let self, outcome.response == .default else { return }
			model.replace(with: channel.config)
		}
	}

	public func windowWillClose(_: Notification) {
		removeConfigurationObserver()
		(delegate as? any ChannelPropertiesSheetDelegate)?.channelPropertiesSheetWillClose(self)
	}
}
