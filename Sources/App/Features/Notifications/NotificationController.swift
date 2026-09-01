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

/** What a delivered notification carries back when the person clicks it.

 `UNNotificationContent.userInfo` is a property-list dictionary, so the keys
 below are the only place the strings appear; every producer and reader inside
 the application works with the value. It used to be an untyped dictionary
 passed whole from the protocol layer to the delegate callback, with each
 reader guessing at the keys. */
public nonisolated struct NotificationPayload: Equatable, Sendable { // nonisolated: value
	static let clientIdentifierKey = "clientId"
	static let channelIdentifierKey = "channelId"
	private static let fileTransferIdentifierKey = "fileTransferUniqueIdentifier"
	private static let fileTransferTypeKey = "fileTransferNotificationType"

	public var clientIdentifier: String?
	public var channelIdentifier: String?
	/// The transfer a file-transfer notification is about, and its event.
	public var fileTransferIdentifier: String?
	public var fileTransferEventRawValue: Int = 0

	public init(
		clientIdentifier: String? = nil,
		channelIdentifier: String? = nil,
		fileTransferIdentifier: String? = nil,
		fileTransferEventRawValue: Int = 0
	) {
		self.clientIdentifier = clientIdentifier
		self.channelIdentifier = channelIdentifier
		self.fileTransferIdentifier = fileTransferIdentifier
		self.fileTransferEventRawValue = fileTransferEventRawValue
	}

	/// Reads a payload back out of the dictionary UserNotifications kept.
	public init(userInfo: [AnyHashable: Any]) {
		clientIdentifier = userInfo[Self.clientIdentifierKey] as? String
		channelIdentifier = userInfo[Self.channelIdentifierKey] as? String
		fileTransferIdentifier = userInfo[Self.fileTransferIdentifierKey] as? String
		fileTransferEventRawValue = (userInfo[Self.fileTransferTypeKey] as? NSNumber)?.intValue ?? 0
	}

	/// The property list UserNotifications stores with the request.
	public var userInfo: [String: PropertyListValue] {
		var result: [String: PropertyListValue] = [:]

		result[Self.clientIdentifierKey] = clientIdentifier.map(PropertyListValue.string)
		result[Self.channelIdentifierKey] = channelIdentifier.map(PropertyListValue.string)
		result[Self.fileTransferIdentifierKey] = fileTransferIdentifier.map(PropertyListValue.string)

		if fileTransferIdentifier != nil {
			result[Self.fileTransferTypeKey] = .integer(fileTransferEventRawValue)
		}

		return result
	}

	/// The notification group this payload belongs to: one thread per channel,
	/// or per client for a notification the whole connection raised.
	public var threadIdentifier: String? {
		guard let clientIdentifier else {
			return nil
		}

		guard let channelIdentifier else {
			return clientIdentifier
		}

		return "\(clientIdentifier)-\(channelIdentifier)"
	}
}

private let fileTransferCategoryIdentifier = "TXNotificationCategoryIdentifierFileTransfer"
private let fileTransferAcceptActionIdentifier = "TXNotificationActionIdentifierFileTransferAccept"
private let privateMessageCategoryIdentifier = "TXNotificationCategoryIdentifierPrivateMessage"
private let privateMessageReplyActionIdentifier = "TXNotificationActionIdentifierPrivateMessageReply"

private nonisolated let notificationControllerLogger = Logger( // nonisolated: let
	subsystem: Bundle.main.bundleIdentifier ?? "Glasstual",
	category: "NotificationController"
)

@MainActor
public final class NotificationController: NSObject, UNUserNotificationCenterDelegate {
	public var areNotificationsDisabled = false

	/** The title/message hash is not unique on its own: repeating the same message in
	 the same channel would otherwise replace the earlier notification. */
	private var notificationSequenceNumber: UInt64 = 0
	/// The main-window selection notification this controller answers.
	private let notifications = NotificationSubscriptions()

	override public init() {
		super.init()

		prepareInitialState()
	}

	isolated deinit {
		notifications.cancelAll()
	}

	private func prepareInitialState() {
		UNUserNotificationCenter.current().delegate = self

		notifications.observe(.mainWindowSelectionChanged) { [weak self] notification in
			self?.mainWindowSelectionChanged(notification)
		}

		/* On a first launch the onboarding window explains the permission
		 before asking for it, so the request is left to that flow. */
		if Preferences.Identity.onboardingCompleted.value {
			Task {
				do {
					let granted = try await UNUserNotificationCenter.current().requestAuthorization(
						options: [.alert, .providesAppNotificationSettings]
					)

					notificationControllerLogger.info("Notification permission: \(granted, privacy: .public)")
				} catch {
					notificationControllerLogger.error(
						"Notifications failed to authorize: \(error.localizedDescription, privacy: .public)"
					)
				}
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

	private func mainWindowSelectionChanged(_: Notification) {
		guard let mainWindow = AppController.shared.mainWindow,
		      let client = mainWindow.selectedClient
		else {
			return
		}

		dismissNotifications(for: mainWindow.selectedChannel, on: client)
	}

	public func title(forEvent event: TXNotificationType) -> String {
		NotificationStrings.eventTypeTitle(for: event)
	}

	public func notify(
		_ eventType: TXNotificationType,
		title eventTitle: String?,
		description eventDescription: String?,
		userInfo eventContext: NotificationPayload?
	) {
		var (title, body) = notificationContent(
			for: eventType,
			title: eventTitle,
			body: eventDescription
		)

		if Preferences.Messages.removeAllFormatting.value == false, let currentBody = body {
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

		scheduleNotification(
			title: title ?? "",
			message: body ?? "",
			userInfo: eventContext,
			notificationIdentifier: nil,
			threadIdentifier: eventContext?.threadIdentifier,
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

	/// The grouping the payload names; kept as a static so callers that hold
	/// two identifiers rather than a payload can ask for it too.
	public static func threadIdentifier(
		forClient clientIdentifier: String?,
		channel channelIdentifier: String?
	) -> String? {
		NotificationPayload(
			clientIdentifier: clientIdentifier,
			channelIdentifier: channelIdentifier
		).threadIdentifier
	}

	public func scheduleNotification(title: String, message: String, userInfo: NotificationPayload?) {
		scheduleNotification(
			title: title,
			message: message,
			userInfo: userInfo,
			notificationIdentifier: nil,
			threadIdentifier: nil,
			categoryIdentifier: nil
		)
	}

	public func scheduleNotification(
		title: String,
		message: String,
		userInfo: NotificationPayload?,
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

	public func scheduleNotification(title: String, message: String, for channel: IRCChannel) {
		guard let client = channel.associatedClient else {
			return
		}

		scheduleNotification(title: title, message: message, for: channel, on: client)
	}

	public func scheduleNotification(title: String, message: String, on client: IRCClient) {
		scheduleNotification(title: title, message: message, for: nil, on: client)
	}

	public func scheduleNotification(
		title: String,
		message: String,
		for channel: IRCChannel?,
		on client: IRCClient
	) {
		let payload = NotificationPayload(
			clientIdentifier: client.uniqueIdentifier,
			channelIdentifier: channel?.uniqueIdentifier
		)

		scheduleNotification(
			title: title,
			message: message,
			userInfo: payload,
			notificationIdentifier: nil,
			threadIdentifier: payload.threadIdentifier,
			categoryIdentifier: nil
		)
	}

	private func scheduleNotification(
		title: String,
		message: String,
		userInfo: NotificationPayload?,
		notificationIdentifier: String?,
		threadIdentifier: String?,
		categoryIdentifier: String?
	) {
		let content = UNMutableNotificationContent()

		content.title = title
		content.body = message

		if let userInfo {
			content.userInfo = userInfo.userInfo.propertyListObject
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

		Task {
			do {
				try await UNUserNotificationCenter.current().add(request)
			} catch {
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
		let payload = NotificationPayload(userInfo: response.notification.request.content.userInfo)

		notificationResponseReceived(
			actionIdentifier: actionIdentifier,
			clientId: payload.clientIdentifier,
			channelId: payload.channelIdentifier,
			fileTransferNotificationType: payload.fileTransferEventRawValue,
			fileTransferUniqueIdentifier: payload.fileTransferIdentifier,
			withReplyMessage: message
		)
	}

	public func dismissNotifications(for channel: IRCChannel?, on client: IRCClient) {
		let clientId = client.uniqueIdentifier
		let channelId = channel?.uniqueIdentifier

		notificationControllerLogger.debug(
			"Dismissing notifications for '\(channelId ?? "<No Channel>", privacy: .public)' on '\(clientId, privacy: .public)'"
		)

		Task {
			let center = UNUserNotificationCenter.current()
			let requests = await center.pendingNotificationRequests()
			let pendingIdentifiers = requests.compactMap { request -> String? in
				Self.isNotification(
					userInfo: request.content.userInfo,
					inScopeOfClientIdentifier: clientId,
					channelIdentifier: channelId
				) ? request.identifier : nil
			}

			if pendingIdentifiers.isEmpty == false {
				center.removePendingNotificationRequests(withIdentifiers: pendingIdentifiers)

				notificationControllerLogger.debug(
					"Dismissed \(pendingIdentifiers.count, privacy: .public) pending notifications"
				)
			}

			let notifications = await center.deliveredNotifications()
			let deliveredIdentifiers = notifications.compactMap { notification -> String? in
				Self.isNotification(
					userInfo: notification.request.content.userInfo,
					inScopeOfClientIdentifier: clientId,
					channelIdentifier: channelId
				) ? notification.request.identifier : nil
			}

			if deliveredIdentifiers.isEmpty == false {
				center.removeDeliveredNotifications(withIdentifiers: deliveredIdentifiers)

				notificationControllerLogger.debug(
					"Dismissed \(deliveredIdentifiers.count, privacy: .public) delivered notifications"
				)
			}
		}
	}

	public nonisolated static func isNotification( // nonisolated: pure
		userInfo: [AnyHashable: Any],
		inScopeOfClientIdentifier clientIdentifier: String,
		channelIdentifier: String?
	) -> Bool {
		let payload = NotificationPayload(userInfo: userInfo)

		/* Equality of nil is valid so both channel IDs can be absent. */
		return clientIdentifier == payload.clientIdentifier && channelIdentifier == payload.channelIdentifier
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

	public func sound(forEvent event: TXNotificationType, in channel: IRCChannel?) -> String? {
		if let channel, let channelValue = channel.config.sound(forEvent: event) {
			return channelValue
		}

		return Preferences.Notifications.sound(event).storedValue
	}

	public func speakEvent(_ event: TXNotificationType, in channel: IRCChannel?) -> Bool {
		resolve(
			event,
			in: channel,
			channelValue: { $0.speakEvent($1) },
			globalValue: { Preferences.Notifications.flag($0, .speak).value }
		)
	}

	public func notificationEnabled(forEvent event: TXNotificationType, in channel: IRCChannel?) -> Bool {
		resolve(
			event,
			in: channel,
			channelValue: { $0.notificationEnabled(forEvent: $1) },
			globalValue: { Preferences.Notifications.flag($0, .enabled).value }
		)
	}

	public func disabledWhileAway(forEvent event: TXNotificationType, in channel: IRCChannel?) -> Bool {
		resolve(
			event,
			in: channel,
			channelValue: { $0.disabledWhileAway(forEvent: $1) },
			globalValue: { Preferences.Notifications.flag($0, .disabledWhileAway).value }
		)
	}

	public func bounceDockIcon(forEvent event: TXNotificationType, in channel: IRCChannel?) -> Bool {
		resolve(
			event,
			in: channel,
			channelValue: { $0.bounceDockIcon(forEvent: $1) },
			globalValue: { Preferences.Notifications.flag($0, .bounceDockIcon).value }
		)
	}

	public func bounceDockIconRepeatedly(forEvent event: TXNotificationType, in channel: IRCChannel?) -> Bool {
		resolve(
			event,
			in: channel,
			channelValue: { $0.bounceDockIconRepeatedly(forEvent: $1) },
			globalValue: { Preferences.Notifications.flag($0, .bounceDockIconRepeatedly).value }
		)
	}

	/// A channel's override wins when it has one; `.inherited` means "no
	/// override", so the application-wide preference answers. Five settings
	/// shared this shape as five byte-identical bodies.
	private func resolve(
		_ event: TXNotificationType,
		in channel: IRCChannel?,
		channelValue: (ChannelConfig, TXNotificationType) -> ChannelEventOverride,
		globalValue: (TXNotificationType) -> Bool
	) -> Bool {
		if let channel {
			switch channelValue(channel.config, event) {
			case .on: return true
			case .off: return false
			case .inherited: break
			}
		}

		return globalValue(event)
	}
}
