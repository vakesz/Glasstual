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

private enum ChannelPropertiesSheetSelection: Int {
	case general = 0
	case defaults = 1
	case notifications = 2
}

@objc(TDCChannelPropertiesSheet)
@MainActor
public final class ChannelPropertiesSheet: SheetBase, NSControlTextEditingDelegate {
	@objc public private(set) var client: IRCClient?
	@objc public private(set) var channel: IRCChannel?
	@objc public private(set) var clientId: String?
	@objc public private(set) var channelId: String?

	/** Accessed from NotificationConfiguration outside the main-actor
	 isolation domain that SheetBase inherits. Config mutations stay on
	 the main thread in practice (sheet UI). */
	@objc public nonisolated(unsafe) var config: MutableChannelConfig!

	private var secretKeyLengthAlertDisplayed = false
	private var navigationTree: [[Any]] = []

	@IBOutlet private var autoJoinCheck: NSButton!
	@IBOutlet private var disableInlineMediaCheck: NSButton!
	@IBOutlet private var enableInlineMediaCheck: NSButton!
	@IBOutlet private var pushNotificationsCheck: NSButton!
	@IBOutlet private var showTreeBadgeCountCheck: NSButton!
	@IBOutlet private var ignoreHighlightsCheck: NSButton!
	@IBOutlet private var ignoreGeneralEventMessagesCheck: NSButton!
	@IBOutlet private var contentViewTabView: NSSegmentedControl!
	@IBOutlet private var channelNameTextField: TVCValidatedTextField!
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

	@objc(initWithClient:)
	public convenience init(client: IRCClient) {
		self.init(config: nil, onClient: client)
	}

	@objc(initWithClientId:)
	public convenience init(clientId: String) {
		self.init(config: nil, onClientWithId: clientId)
	}

	@objc(initWithChannel:)
	public init(channel: IRCChannel) {
		super.init(window: nil)

		client = channel.associatedClient
		clientId = channel.associatedClient?.uniqueIdentifier
		self.channel = channel
		channelId = channel.uniqueIdentifier
		config = channel.config.mutableCopy() as? MutableChannelConfig ?? MutableChannelConfig()

		prepareInitialState()
		loadConfig()
	}

	@objc(initWithConfig:)
	public convenience init(config: ChannelConfig?) {
		self.init(config: config, onClientWithId: nil)
	}

	@objc(initWithConfig:onClient:)
	public init(config: ChannelConfig?, onClient client: IRCClient?) {
		super.init(window: nil)

		self.client = client
		clientId = client?.uniqueIdentifier

		if let config {
			self.config = config.mutableCopy() as? MutableChannelConfig ?? MutableChannelConfig()
		} else {
			self.config = MutableChannelConfig()
		}

		prepareInitialState()
		loadConfig()
	}

	@objc(initWithConfig:onClientWithId:)
	public convenience init(config: ChannelConfig?, onClientWithId clientId: String?) {
		self.init(config: config, onClient: nil)
		self.clientId = clientId
	}

	private func prepareInitialState() {
		Bundle.main.loadNibNamed("TDCChannelPropertiesSheet", owner: self, topLevelObjects: nil)

		navigationTree = [
			[contentViewGeneralView as Any, channelNameTextField as Any],
			[contentViewDefaultsView as Any, defaultTopicTextField as Any],
			[contentViewNotifications as Any, NSNull()],
		]

		channelNameTextField.stringValueIsInvalidOnEmpty = true
		channelNameTextField.stringValueUsesOnlyFirstToken = true
		channelNameTextField.textDidChangeCallback = self

		channelNameTextField.validationBlock = { currentValue in
			if (currentValue as NSString).isChannelName == false {
				return LocalizedKey("TDCChannelPropertiesSheet[1nd-7x]")
			}

			return nil
		}

		addConfigurationDidChangeObserver()
		setupNotificationsController()
	}

	private func setupNotificationsController() {
		notificationsController.allowsMixedState = true

		var notifications: [Any] = []
		notifications.append(
			ChannelPropertiesNotificationConfiguration(eventType: .highlight, in: self)
		)
		notifications.append(" ")
		notifications.append(
			ChannelPropertiesNotificationConfiguration(eventType: .channelMessage, in: self)
		)
		notifications.append(
			ChannelPropertiesNotificationConfiguration(eventType: .channelNotice, in: self)
		)
		notifications.append(" ")
		notifications.append(
			ChannelPropertiesNotificationConfiguration(eventType: .userJoined, in: self)
		)
		notifications.append(
			ChannelPropertiesNotificationConfiguration(eventType: .userParted, in: self)
		)

		notificationsController.notifications = notifications
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
		guard selection.rawValue < navigationTree.count else {
			return
		}

		let entry = navigationTree[selection.rawValue]
		if let view = entry[0] as? NSView {
			selectPane(view)
		}

		if let firstResponder = entry[1] as? NSControl {
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
			body: LocalizedKey("TDCChannelPropertiesSheet[op4-gg]"),
			title: LocalizedKey(
				"TDCChannelPropertiesSheet[zf2-r7]",
				client.networkNameAlt,
				maximumKeyLength
			),
			defaultButton: LocalizedKey("Prompts[c7s-dq]"),
			alternateButton: nil,
			otherButton: nil,
			suppressionKey: "maximum_secret_key_length",
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
			name: .IRCChannelConfigurationWasUpdated,
			object: channel
		)
	}

	private func removeConfigurationDidChangeObserver() {
		NotificationCenter.default.removeObserver(
			self,
			name: .IRCChannelConfigurationWasUpdated,
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
			body: LocalizedKey("TDCChannelPropertiesSheet[qby-hi]"),
			title: LocalizedKey("TDCChannelPropertiesSheet[mvl-r5]"),
			defaultButton: LocalizedKey("Prompts[mvh-ms]"),
			alternateButton: LocalizedKey("Prompts[99q-gg]"),
			otherButton: nil
		) { [weak self] buttonClicked, _, _ in
			guard let self, buttonClicked == .default else {
				return
			}

			close()
			config = channel.config.mutableCopy() as? MutableChannelConfig ?? MutableChannelConfig()
			loadConfig()
			reloadNotificationsController()
			start()
		}
	}

	@IBAction
	private func onInlineMediaCheckChanged(_: Any?) {
		guard enableInlineMediaCheck.state == .on else {
			return
		}

		LogControllerInlineMediaService.askPermissionToEnableInlineMedia { [weak self] granted in
			XRPerformBlockAsynchronouslyOnMainQueue {
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

		let selector = NSSelectorFromString("channelPropertiesSheet:onOk:")
		if let delegate, delegate.responds(to: selector) {
			_ = delegate.perform(selector, with: self, with: config.copy())
		}

		super.ok(nil)
	}

	private func okOrError() -> Bool {
		okOrError(for: channelNameTextField, in: .general)
	}

	private func okOrError(
		for textField: TVCValidatedTextField,
		in selection: ChannelPropertiesSheetSelection
	) -> Bool {
		if textField.valueIsValid {
			return true
		}

		navigateToSelection(selection)

		XRPerformBlockAsynchronouslyOnMainQueue {
			textField.showValidationErrorPopover()
		}

		return false
	}

	@objc
	public func windowWillClose(_: Notification) {
		removeConfigurationDidChangeObserver()
		sheet.makeFirstResponder(nil)

		let selector = NSSelectorFromString("channelPropertiesSheetWillClose:")
		if let delegate, delegate.responds(to: selector) {
			_ = delegate.perform(selector, with: self)
		}
	}
}
