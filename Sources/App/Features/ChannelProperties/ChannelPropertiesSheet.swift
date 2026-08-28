/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \\ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\\___/_/\\_\\__|\\__,_|\\__,_|_|
 *
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 *********************************************************************** */

import AppKit
import CocoaExtensions

private enum ChannelPropertiesSheetSelection: Int {
	case general = 0
	case defaults = 1
	case notifications = 2
}

/// One pane of the channel-properties sheet: the view it shows and the control
/// that takes focus when it appears. This used to be a `[[Any]]` indexed
/// positionally, with `NSNull()` where a pane wanted no focused control.
@MainActor
private struct ChannelPropertiesPane {
	let view: NSView
	let firstResponder: NSControl?
}

/// What `ChannelPropertiesSheet` reports back. The configuration is a value
/// type, so it cannot travel through `perform(_:with:with:)`.
@MainActor
public protocol ChannelPropertiesSheetDelegate: AnyObject {
	func channelPropertiesSheet(_ sender: ChannelPropertiesSheet, onOk config: ChannelConfig)
	func channelPropertiesSheetWillClose(_ sender: ChannelPropertiesSheet)
}

@objc(TDCChannelPropertiesSheet)
@MainActor
public final class ChannelPropertiesSheet: SheetBase, NSControlTextEditingDelegate, TDCChannelPrototype {
	@objc public private(set) var client: IRCClient?
	@objc public private(set) var channel: IRCChannel?
	@objc public private(set) var clientId: String?
	@objc public private(set) var channelId: String?

	public var config: ChannelConfig

	private var secretKeyLengthAlertDisplayed = false
	private var panes: [ChannelPropertiesPane] = []

	@IBOutlet private var autoJoinCheck: NSButton!
	@IBOutlet private var disableInlineMediaCheck: NSButton!
	@IBOutlet private var enableInlineMediaCheck: NSButton!
	@IBOutlet private var pushNotificationsCheck: NSButton!
	@IBOutlet private var showTreeBadgeCountCheck: NSButton!
	@IBOutlet private var ignoreHighlightsCheck: NSButton!
	@IBOutlet private var ignoreGeneralEventMessagesCheck: NSButton!
	@IBOutlet private var contentViewTabView: NSSegmentedControl!
	@IBOutlet private var channelNameTextField: ValidatedTextField!
	@IBOutlet private var labelTextField: NSTextField!
	@IBOutlet private var defaultModesTextField: NSTextField!
	@IBOutlet private var defaultTopicTextField: NSTextField!
	@IBOutlet private var secretKeyTextField: NSTextField!
	@IBOutlet private var contentView: NSView!
	@IBOutlet private var contentViewDefaultsView: NSView!
	@IBOutlet private var contentViewGeneralView: NSView!
	@IBOutlet private var contentViewNotifications: NSView!
	@IBOutlet private var contentViewNotificationsHost: NSView!
	@IBOutlet private var notificationsController: NotificationConfigurationViewController!

	public convenience init(client: IRCClient) {
		self.init(config: nil, onClient: client)
	}

	public convenience init(clientId: String) {
		self.init(config: nil, onClientWithId: clientId)
	}

	public init(channel: IRCChannel) {
		config = channel.config

		super.init(window: nil)

		client = channel.associatedClient
		clientId = channel.associatedClient?.uniqueIdentifier
		self.channel = channel
		channelId = channel.uniqueIdentifier

		prepareInitialState()
		loadConfig()
	}

	public convenience init(config: ChannelConfig?) {
		self.init(config: config, onClientWithId: nil)
	}

	public init(config: ChannelConfig?, onClient client: IRCClient?) {
		self.config = config ?? ChannelConfig()

		super.init(window: nil)

		self.client = client
		clientId = client?.uniqueIdentifier

		prepareInitialState()
		loadConfig()
	}

	public convenience init(config: ChannelConfig?, onClientWithId clientId: String?) {
		self.init(config: config, onClient: nil)
		self.clientId = clientId
	}

	private func prepareInitialState() {
		Bundle.main.loadNibNamed("TDCChannelPropertiesSheet", owner: self, topLevelObjects: nil)

		panes = [
			ChannelPropertiesPane(view: contentViewGeneralView, firstResponder: channelNameTextField),
			ChannelPropertiesPane(view: contentViewDefaultsView, firstResponder: defaultTopicTextField),
			ChannelPropertiesPane(view: contentViewNotifications, firstResponder: nil),
		]

		channelNameTextField.stringValueIsInvalidOnEmpty = true
		channelNameTextField.stringValueUsesOnlyFirstToken = true

		channelNameTextField.validationBlock = { currentValue in
			if (currentValue as NSString).isChannelName == false {
				return ChannelPropertiesStrings.invalidChannelName
			}

			return nil
		}

		addConfigurationDidChangeObserver()
		setupNotificationsController()
	}

	private func setupNotificationsController() {
		notificationsController.allowsMixedState = true

		notificationsController.notifications = [
			.configuration(ChannelNotificationConfiguration(eventType: .highlight, in: self)),
			.separator,
			.configuration(ChannelNotificationConfiguration(eventType: .channelMessage, in: self)),
			.configuration(ChannelNotificationConfiguration(eventType: .channelNotice, in: self)),
			.separator,
			.configuration(ChannelNotificationConfiguration(eventType: .userJoined, in: self)),
			.configuration(ChannelNotificationConfiguration(eventType: .userParted, in: self)),
		]
		notificationsController.attachToView(contentViewNotificationsHost)
	}

	private func reloadNotificationsController() {
		notificationsController.reload()
	}

	private func updateNavigationEnabledState() {
		contentViewTabView.setEnabled(
			pushNotificationsCheck.state == .on,
			forSegment: ChannelPropertiesSheetSelection.notifications.rawValue
		)
	}

	private func loadConfig() {
		channelNameTextField.stringValue = config.channelName
		channelNameTextField.isEditable = config.channelName.isEmpty

		labelTextField.stringValue = config.label ?? ""
		defaultModesTextField.stringValue = config.defaultModes ?? ""
		defaultTopicTextField.stringValue = config.defaultTopic ?? ""
		secretKeyTextField.stringValue = config.secretKey ?? ""

		autoJoinCheck.state = config.autoJoin ? .on : .off
		pushNotificationsCheck.state = config.pushNotifications ? .on : .off
		showTreeBadgeCountCheck.state = config.showTreeBadgeCount ? .on : .off
		ignoreGeneralEventMessagesCheck.state = config.ignoreGeneralEventMessages ? .on : .off
		ignoreHighlightsCheck.state = config.ignoreHighlights ? .on : .off
		disableInlineMediaCheck.state = config.inlineMediaDisabled ? .on : .off
		enableInlineMediaCheck.state = config.inlineMediaEnabled ? .on : .off

		updateNavigationEnabledState()
	}

	@IBAction
	private func onMenuBarItemChanged(_ sender: NSSegmentedControl?) {
		let selection = ChannelPropertiesSheetSelection(rawValue: sender?.selectedSegment ?? 0) ?? .general
		navigateToSelection(selection, force: true)
	}

	private func navigateToSelection(_ selection: ChannelPropertiesSheetSelection, force: Bool = false) {
		if force == false, contentViewTabView.selectedSegment == selection.rawValue {
			return
		}

		contentViewTabView.selectedSegment = selection.rawValue
		performNavigate(to: selection)
	}

	private func performNavigate(to selection: ChannelPropertiesSheetSelection) {
		guard panes.indices.contains(Int(selection.rawValue)) else {
			return
		}

		let pane = panes[Int(selection.rawValue)]
		selectPane(pane.view)

		if let firstResponder = pane.firstResponder {
			sheet.makeFirstResponder(firstResponder)
		}
	}

	private func selectPane(_ view: NSView) {
		contentView.replaceFirstSubview(view)
	}

	@objc
	public func start() {
		startSheet()
		performNavigate(to: .general)
	}

	public func controlTextDidChange(_ notification: Notification) {
		if notification.object as AnyObject? === secretKeyTextField {
			updateSecretKeyLengthAlert()
		}
	}

	private func updateSecretKeyLengthAlert() {
		guard let client else {
			return
		}

		let maximumKeyLength = client.supportInfo.maximumKeyLength
		if maximumKeyLength == 0 {
			return
		}

		if secretKeyTextField.stringValue.count <= maximumKeyLength {
			return
		}

		if secretKeyLengthAlertDisplayed == false {
			secretKeyLengthAlertDisplayed = true
		} else {
			return
		}

		TDCAlert.alertSheet(
			with: sheet,
			body: ChannelValidationStrings.maximumKeyLengthMessage,
			title: ChannelValidationStrings.maximumKeyLengthTitle(
				networkName: client.networkNameAlt,
				maximumLength: Int(clamping: maximumKeyLength)
			),
			defaultButton: PromptStrings.Action.confirmation,
			alternateButton: nil,
			otherButton: nil,
			suppressionKey: ChannelValidationSuppressionKey.maximumSecretKeyLength.rawValue,
			suppressionText: nil,
			completionBlock: nil
		)
	}

	private func addConfigurationDidChangeObserver() {
		guard let channel else {
			return
		}

		NotificationCenter.default.addObserver(
			self,
			selector: #selector(underlyingConfigurationChanged(_:)),
			name: .ircChannelConfigurationWasUpdated,
			object: channel
		)
	}

	private func removeConfigurationDidChangeObserver() {
		NotificationCenter.default.removeObserver(
			self,
			name: .ircChannelConfigurationWasUpdated,
			object: nil
		)
	}

	@objc
	private func underlyingConfigurationChanged(_ notification: Notification) {
		guard let channel = notification.object as? IRCChannel else {
			return
		}

		guard let window = sheet else {
			return
		}

		TDCAlert.alertSheet(
			with: window,
			body: ChannelPropertiesStrings.unsavedChangesWarning,
			title: ChannelPropertiesStrings.configurationChangedTitle,
			defaultButton: PromptStrings.Action.yes,
			alternateButton: PromptStrings.Action.no,
			otherButton: nil
		) { [weak self] outcome in
			guard let self, outcome.response == .default else {
				return
			}

			/* Reload in place. Closing and re-opening the same window in one turn made
			 AppKit reject the second beginSheet (endSheet is asynchronous), and cancel()
			 had already torn down the configuration observer. */
			config = channel.config
			loadConfig()
			reloadNotificationsController()
		}
	}

	@IBAction
	private func onInlineMediaCheckChanged(_: Any?) {
		guard enableInlineMediaCheck.state == .on else {
			return
		}

		LogControllerInlineMediaService.askPermissionToEnableInlineMedia { [weak self] granted in
			Task { @MainActor [weak self] in
				if granted == false {
					self?.enableInlineMediaCheck.state = .off
				}
			}
		}
	}

	@IBAction
	private func onPushNotificationsCheckChanged(_: Any?) {
		updateNavigationEnabledState()
	}

	@IBAction override public func cancel(_ sender: Any?) {
		removeConfigurationDidChangeObserver()
		super.cancel(sender)
	}

	@IBAction override public func ok(_: Any?) {
		guard okOrError() else {
			return
		}

		removeConfigurationDidChangeObserver()

		config.channelName = channelNameTextField.value
		config.label = labelTextField.trimmedStringValue
		config.defaultModes = defaultModesTextField.trimmedStringValue
		config.defaultTopic = defaultTopicTextField.trimmedStringValue
		config.secretKey = secretKeyTextField.trimmedFirstTokenStringValue

		config.autoJoin = (autoJoinCheck.state == .on)
		config.pushNotifications = (pushNotificationsCheck.state == .on)
		config.showTreeBadgeCount = (showTreeBadgeCountCheck.state == .on)
		config.ignoreGeneralEventMessages = (ignoreGeneralEventMessagesCheck.state == .on)
		config.ignoreHighlights = (ignoreHighlightsCheck.state == .on)
		config.inlineMediaDisabled = (disableInlineMediaCheck.state == .on)
		config.inlineMediaEnabled = (enableInlineMediaCheck.state == .on)

		(delegate as? any ChannelPropertiesSheetDelegate)?.channelPropertiesSheet(self, onOk: config)

		super.ok(nil)
	}

	private func okOrError() -> Bool {
		okOrError(for: channelNameTextField, in: .general)
	}

	private func okOrError(
		for textField: ValidatedTextField,
		in selection: ChannelPropertiesSheetSelection
	) -> Bool {
		if textField.valueIsValid {
			return true
		}

		navigateToSelection(selection)

		performAsynchronouslyOnMainQueue {
			textField.showValidationErrorPopover()
		}

		return false
	}

	@objc
	public func windowWillClose(_: Notification) {
		removeConfigurationDidChangeObserver()
		sheet.makeFirstResponder(nil)

		(delegate as? any ChannelPropertiesSheetDelegate)?.channelPropertiesSheetWillClose(self)
	}
}
