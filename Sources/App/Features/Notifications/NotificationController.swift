/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 *********************************************************************** */

import AppKit
import CocoaExtensions
import os
import UserNotifications

nonisolated enum NotificationPayload { // nonisolated: value
	static let clientIdentifierKey = "clientId"
	static let channelIdentifierKey = "channelId"
}

private let fileTransferCategoryIdentifier = "TXNotificationCategoryIdentifierFileTransfer"
private let fileTransferAcceptActionIdentifier = "TXNotificationActionIdentifierFileTransferAccept"
private let privateMessageCategoryIdentifier = "TXNotificationCategoryIdentifierPrivateMessage"
private let privateMessageReplyActionIdentifier = "TXNotificationActionIdentifierPrivateMessageReply"

private nonisolated let notificationControllerLogger = Logger( // nonisolated: let
	subsystem: Bundle.main.bundleIdentifier ?? "Glasstual",
	category: "NotificationController"
)

@objc(TLONotificationController)
@MainActor
public final class NotificationController: NSObject, UNUserNotificationCenterDelegate {
	@objc public var areNotificationsDisabled = false

	/** The title/message hash is not unique on its own: repeating the same message in
	 the same channel would otherwise replace the earlier notification. */
	private var notificationSequenceNumber: UInt64 = 0

	override public init() {
		super.init()

		prepareInitialState()
	}

	deinit {
		NotificationCenter.default.removeObserver(self)
	}

	private func prepareInitialState() {
		UNUserNotificationCenter.current().delegate = self

		NotificationCenter.default.addObserver(
			self,
			selector: #selector(mainWindowSelectionChanged(_:)),
			name: .TVCMainWindowSelectionChanged,
			object: nil
		)

		/* On a first launch the onboarding window explains the permission
		 before asking for it, so the request is left to that flow. */
		if TextualPreferences.onboardingCompleted() {
			UNUserNotificationCenter.current().requestAuthorization(
				options: [.alert, .providesAppNotificationSettings]
			) { granted, error in
				if let error {
					notificationControllerLogger.error(
						"Notifications failed to authorize: \(error.localizedDescription, privacy: .public)"
					)
				}

				notificationControllerLogger.info("Notification permission: \(granted, privacy: .public)")
			}
		}

		registerCategories()
	}

	private var categoriesToRegister: Set<UNNotificationCategory> {
		let fileTransferAcceptAction = UNNotificationAction(
			identifier: fileTransferAcceptActionIdentifier,
			title: PromptStrings.Action.accept,
			options: []
		)

		let fileTransferCategory = UNNotificationCategory(
			identifier: fileTransferCategoryIdentifier,
			actions: [fileTransferAcceptAction],
			intentIdentifiers: [],
			options: [.customDismissAction]
		)

		let privateMessageReplyAction = UNTextInputNotificationAction(
			identifier: privateMessageReplyActionIdentifier,
			title: NotificationStrings.replyActionTitle,
			options: [],
			textInputButtonTitle: NotificationStrings.replySendButtonTitle,
			textInputPlaceholder: NotificationStrings.replyPlaceholder
		)

		let privateMessageCategory = UNNotificationCategory(
			identifier: privateMessageCategoryIdentifier,
			actions: [privateMessageReplyAction],
			intentIdentifiers: [],
			options: [.customDismissAction]
		)

		return [fileTransferCategory, privateMessageCategory]
	}

	private func registerCategories() {
		UNUserNotificationCenter.current().setNotificationCategories(categoriesToRegister)
	}

	@objc
	private func mainWindowSelectionChanged(_: Notification) {
		guard let mainWindow = AppController.shared.mainWindow,
		      let client = mainWindow.selectedClient
		else {
			return
		}

		dismissNotifications(for: mainWindow.selectedChannel, on: client)
	}

	@objc(titleForEvent:)
	public func title(forEvent event: TXNotificationType) -> String {
		NotificationStrings.eventTypeTitle(for: event)
	}

	@objc(notify:title:description:userInfo:)
	public func notify(
		_ eventType: TXNotificationType,
		title eventTitle: String?,
		description eventDescription: String?,
		userInfo eventContext: [String: Any]?
	) {
		var (title, body) = notificationContent(
			for: eventType,
			title: eventTitle,
			body: eventDescription
		)

		if TextualPreferences.removeAllFormatting() == false, let currentBody = body {
			body = (currentBody as NSString).stripIRCEffects
		}

		let categoryIdentifier: String? = switch eventType {
		case .fileTransferReceiveRequested:
			fileTransferCategoryIdentifier
		case .newPrivateMessage, .privateMessage:
			privateMessageCategoryIdentifier
		default:
			nil
		}

		let clientId = eventContext?[NotificationPayload.clientIdentifierKey] as? String
		let channelId = eventContext?[NotificationPayload.channelIdentifierKey] as? String
		let threadIdentifier = Self.threadIdentifier(forClient: clientId, channel: channelId)

		scheduleNotification(
			title: title ?? "",
			message: body ?? "",
			userInfo: eventContext,
			notificationIdentifier: nil,
			threadIdentifier: threadIdentifier,
			categoryIdentifier: categoryIdentifier
		)
	}

	private func notificationContent(
		for eventType: TXNotificationType,
		title eventTitle: String?,
		body eventBody: String?
	) -> (title: String?, body: String?) {
		(
			NotificationStrings.deliveredTitle(for: eventType, subject: eventTitle),
			NotificationStrings.deliveredBody(for: eventType, fallback: eventBody)
		)
	}

	@objc(threadIdentifierForClient:channel:)
	public static func threadIdentifier(forClient clientIdentifier: String?, channel channelIdentifier: String?)
		-> String?
	{
		guard let clientIdentifier else {
			return nil
		}

		if let channelIdentifier {
			return "\(clientIdentifier)-\(channelIdentifier)"
		}

		return clientIdentifier
	}

	@objc(scheduleNotificationWithTitle:message:userInfo:)
	public func scheduleNotification(title: String, message: String, userInfo: [String: Any]?) {
		scheduleNotification(
			title: title,
			message: message,
			userInfo: userInfo,
			notificationIdentifier: nil,
			threadIdentifier: nil,
			categoryIdentifier: nil
		)
	}

	@objc(scheduleNotificationWithTitle:message:userInfo:threadIdentifier:)
	public func scheduleNotification(
		title: String,
		message: String,
		userInfo: [String: Any]?,
		threadIdentifier: String
	) {
		scheduleNotification(
			title: title,
			message: message,
			userInfo: userInfo,
			notificationIdentifier: nil,
			threadIdentifier: threadIdentifier,
			categoryIdentifier: nil
		)
	}

	@objc(scheduleNotificationWithTitle:message:forChannel:)
	public func scheduleNotification(title: String, message: String, for channel: IRCChannel) {
		guard let client = channel.associatedClient else {
			return
		}

		scheduleNotification(title: title, message: message, for: channel, on: client)
	}

	@objc(scheduleNotificationWithTitle:message:onClient:)
	public func scheduleNotification(title: String, message: String, on client: IRCClient) {
		scheduleNotification(title: title, message: message, for: nil, on: client)
	}

	@objc(scheduleNotificationWithTitle:message:forChannel:onClient:)
	public func scheduleNotification(
		title: String,
		message: String,
		for channel: IRCChannel?,
		on client: IRCClient
	) {
		let clientId = client.uniqueIdentifier
		let channelId = channel?.uniqueIdentifier
		let threadIdentifier = Self.threadIdentifier(forClient: clientId, channel: channelId)

		let userInfo: [String: Any] = if let channelId {
			[
				NotificationPayload.clientIdentifierKey: clientId,
				NotificationPayload.channelIdentifierKey: channelId,
			]
		} else {
			[NotificationPayload.clientIdentifierKey: clientId]
		}

		scheduleNotification(
			title: title,
			message: message,
			userInfo: userInfo,
			notificationIdentifier: nil,
			threadIdentifier: threadIdentifier,
			categoryIdentifier: nil
		)
	}

	private func scheduleNotification(
		title: String,
		message: String,
		userInfo: [String: Any]?,
		notificationIdentifier: String?,
		threadIdentifier: String?,
		categoryIdentifier: String?
	) {
		let content = UNMutableNotificationContent()

		content.title = title
		content.body = message

		if let userInfo {
			content.userInfo = userInfo
		}

		if let categoryIdentifier {
			content.categoryIdentifier = categoryIdentifier
		}

		if let threadIdentifier {
			content.threadIdentifier = threadIdentifier
		}

		/* The notification identifier should be unique to the specific notification
		 because otherwise the system will replace existing notifications of the
		 same identifier. That's not a bad behavior. Just not one we want. */
		/* Glasstual will format the identifier as such:
		 TXNotification[-<clientID>[-<channelId>]]-<eventTitle hash>-<eventDescription hash> */
		let identifier: String
		if let notificationIdentifier {
			identifier = notificationIdentifier
		} else {
			notificationSequenceNumber &+= 1
			let scope = Self.notificationIdentifier(
				title: title,
				message: message,
				threadIdentifier: threadIdentifier
			)
			identifier = "\(scope)-\(notificationSequenceNumber)"
		}

		scheduleNotification(content: content, identifier: identifier)
	}

	@objc(notificationIdentifierWithTitle:message:threadIdentifier:)
	public static func notificationIdentifier(
		title: String,
		message: String,
		threadIdentifier: String?
	) -> String {
		let thread = threadIdentifier ?? "<No Thread>"
		let titleHash = (title as NSString).hash
		let messageHash = (message as NSString).hash

		return String(format: "TXNotification-%@-%ld-%ld", thread, titleHash, messageHash)
	}

	private func scheduleNotification(content: UNNotificationContent, identifier: String) {
		let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)

		scheduleNotification(request: request)
	}

	private func scheduleNotification(request: UNNotificationRequest) {
		let title = request.content.title

		UNUserNotificationCenter.current().add(request) { error in
			if let error {
				notificationControllerLogger.error(
					"Failed to post notification '\(title, privacy: .private)': \(error.localizedDescription, privacy: .public)"
				)
			}
		}
	}

	// MARK: - Notification Center Delegate

	public func userNotificationCenter(
		_: UNUserNotificationCenter,
		openSettingsFor _: UNNotification?
	) {
		AppController.shared.menuController?.showNotificationPreferences(nil)
	}

	public func userNotificationCenter(
		_: UNUserNotificationCenter,
		willPresent _: UNNotification
	) async -> UNNotificationPresentationOptions {
		[.list, .banner]
	}

	public func userNotificationCenter(
		_: UNUserNotificationCenter,
		didReceive response: UNNotificationResponse
	) async {
		let actionIdentifier = response.actionIdentifier
		let message = (response as? UNTextInputNotificationResponse)?.userText
		let userInfo = response.notification.request.content.userInfo

		let clientId = userInfo[NotificationPayload.clientIdentifierKey] as? String
		let channelId = userInfo[NotificationPayload.channelIdentifierKey] as? String
		let fileTransferNotificationType = (userInfo as NSDictionary).ce_integer(
			forKey: "fileTransferNotificationType"
		)
		let fileTransferUniqueIdentifier = userInfo["fileTransferUniqueIdentifier"] as? String

		notificationResponseReceived(
			actionIdentifier: actionIdentifier,
			clientId: clientId,
			channelId: channelId,
			fileTransferNotificationType: fileTransferNotificationType,
			fileTransferUniqueIdentifier: fileTransferUniqueIdentifier,
			withReplyMessage: message
		)
	}

	@objc(dismissNotificationsForChannel:onClient:)
	public func dismissNotifications(for channel: IRCChannel?, on client: IRCClient) {
		let clientId = client.uniqueIdentifier
		let channelId = channel?.uniqueIdentifier

		notificationControllerLogger.debug(
			"Dismissing notifications for '\(channelId ?? "<No Channel>", privacy: .public)' on '\(clientId, privacy: .public)'"
		)

		UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
			let identifiers = requests.compactMap { request -> String? in
				Self.isNotification(
					userInfo: request.content.userInfo,
					inScopeOfClientIdentifier: clientId,
					channelIdentifier: channelId
				) ? request.identifier : nil
			}

			guard !identifiers.isEmpty else {
				return
			}

			UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: identifiers)

			notificationControllerLogger.debug("Dismissed \(identifiers.count, privacy: .public) pending notifications")
		}

		UNUserNotificationCenter.current().getDeliveredNotifications { notifications in
			let identifiers = notifications.compactMap { notification -> String? in
				Self.isNotification(
					userInfo: notification.request.content.userInfo,
					inScopeOfClientIdentifier: clientId,
					channelIdentifier: channelId
				) ? notification.request.identifier : nil
			}

			guard !identifiers.isEmpty else {
				return
			}

			UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: identifiers)

			notificationControllerLogger.debug(
				"Dismissed \(identifiers.count, privacy: .public) delivered notifications"
			)
		}
	}

	@objc(userInfo:isInScopeOfClientIdentifier:channelIdentifier:)
	public nonisolated static func isNotification( // nonisolated: pure
		userInfo: [AnyHashable: Any],
		inScopeOfClientIdentifier clientIdentifier: String,
		channelIdentifier: String?
	) -> Bool {
		let clientIdRight = userInfo[NotificationPayload.clientIdentifierKey] as? String
		let channelIdRight = userInfo[NotificationPayload.channelIdentifierKey] as? String

		/* Equality of nil is valid so both channel IDs can be absent. */
		return clientIdentifier == clientIdRight && channelIdentifier == channelIdRight
	}

	// MARK: - Notification Callback

	private func notificationResponseReceived(
		actionIdentifier: String,
		clientId: String?,
		channelId: String?,
		fileTransferNotificationType: Int,
		fileTransferUniqueIdentifier: String?,
		withReplyMessage message: String?
	) {
		if actionIdentifier == UNNotificationDismissActionIdentifier {
			notificationControllerLogger.debug(
				"Dismissed notification action: '\(actionIdentifier, privacy: .private)'"
			)

			return
		}

		/* If we ever expand beyond a few different actions, then revisit
		 this so that we aren't just declaring a bunch of booleans.
		 This was just the easier solution at the time. */
		let isFileTransferAction = actionIdentifier == fileTransferAcceptActionIdentifier
		let isPrivateMessageAction = actionIdentifier == privateMessageReplyActionIdentifier

		let activateApp = !isPrivateMessageAction
		let keyMainWindow = !isPrivateMessageAction && !isFileTransferAction

		if activateApp {
			NSApp.activate()
		}

		if keyMainWindow {
			AppController.shared.mainWindow.makeKeyAndOrderFront(nil)
		}

		/* Handle file transfer notifications allowing the user to start a
		 file transfer directly through the notification's action button. */
		if isFileTransferAction {
			SharedApplication.sharedFileTransferDialog().show(true, restorePosition: false)

			guard fileTransferNotificationType == TXNotificationType.fileTransferReceiveRequested.rawValue else {
				return
			}

			guard let fileTransferUniqueIdentifier else {
				return
			}

			guard
				let fileTransfer = SharedApplication.sharedFileTransferDialog()
				.fileTransfer(withUniqueIdentifier: fileTransferUniqueIdentifier)
			else {
				return
			}

			guard fileTransfer.transferStatus == .stopped else {
				return
			}

			fileTransfer.openWithPathOrUserDownloads()

			return
		}

		/* Handle all other IRC related notifications. */
		guard let clientId else {
			return
		}

		let world = AppController.shared.world!

		let channel: IRCChannel?
		let client: IRCClient?

		if let channelId {
			channel = world.findChannel(withId: channelId, onClientWithId: clientId)
			client = nil
		} else {
			channel = nil
			client = world.findClient(withId: clientId)
		}

		if let channel {
			let treeItem: TreeItem = channel
			AppController.shared.mainWindow.select(treeItem)
		} else if let client {
			AppController.shared.mainWindow.select(client)
		}

		guard let channel else {
			return
		}

		guard let message, !message.isEmpty else {
			return
		}

		let treeItem: TreeItem = channel
		channel.associatedClient?.inputText(message, destination: treeItem)
	}

	// MARK: - Preferences

	@objc(soundForEvent:inChannel:)
	public func sound(forEvent event: TXNotificationType, in channel: IRCChannel?) -> String? {
		if let channel, let channelValue = channel.config.sound(forEvent: event) {
			return channelValue
		}

		return TextualPreferences.sound(for: event)
	}

	@objc(speakEvent:inChannel:)
	public func speakEvent(_ event: TXNotificationType, in channel: IRCChannel?) -> Bool {
		resolve(
			event,
			in: channel,
			channelValue: { $0.speakEvent($1) },
			globalValue: TextualPreferences.speak
		)
	}

	@objc(notificationEnabledForEvent:inChannel:)
	public func notificationEnabled(forEvent event: TXNotificationType, in channel: IRCChannel?) -> Bool {
		resolve(
			event,
			in: channel,
			channelValue: { $0.notificationEnabled(forEvent: $1) },
			globalValue: TextualPreferences.notificationEnabled(for:)
		)
	}

	@objc(disabledWhileAwayForEvent:inChannel:)
	public func disabledWhileAway(forEvent event: TXNotificationType, in channel: IRCChannel?) -> Bool {
		resolve(
			event,
			in: channel,
			channelValue: { $0.disabledWhileAway(forEvent: $1) },
			globalValue: TextualPreferences.disabledWhileAway(for:)
		)
	}

	@objc(bounceDockIconForEvent:inChannel:)
	public func bounceDockIcon(forEvent event: TXNotificationType, in channel: IRCChannel?) -> Bool {
		resolve(
			event,
			in: channel,
			channelValue: { $0.bounceDockIcon(forEvent: $1) },
			globalValue: TextualPreferences.bounceDockIcon(for:)
		)
	}

	@objc(bounceDockIconRepeatedlyForEvent:inChannel:)
	public func bounceDockIconRepeatedly(forEvent event: TXNotificationType, in channel: IRCChannel?) -> Bool {
		resolve(
			event,
			in: channel,
			channelValue: { $0.bounceDockIconRepeatedly(forEvent: $1) },
			globalValue: TextualPreferences.bounceDockIconRepeatedly(for:)
		)
	}

	/// A channel's override wins when it has one; `.mixed` means "no override",
	/// so the application-wide preference answers. Five settings shared this
	/// shape as five byte-identical bodies.
	private func resolve(
		_ event: TXNotificationType,
		in channel: IRCChannel?,
		channelValue: (ChannelConfig, TXNotificationType) -> NSControl.StateValue,
		globalValue: (TXNotificationType) -> Bool
	) -> Bool {
		if let channel {
			let override = channelValue(channel.config, event)

			if override != .mixed {
				return override == .on
			}
		}

		return globalValue(event)
	}
}
