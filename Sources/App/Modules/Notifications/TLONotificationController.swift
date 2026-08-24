/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \\ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\\___/_/\\_\\__|\\__,_|\\__,_|_|
 *
 * Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 *********************************************************************** */

import AppKit
import os
import UserNotifications

private let fileTransferCategoryIdentifier = "TXNotificationCategoryIdentifierFileTransfer"
private let fileTransferAcceptActionIdentifier = "TXNotificationActionIdentifierFileTransferAccept"
private let privateMessageCategoryIdentifier = "TXNotificationCategoryIdentifierPrivateMessage"
private let privateMessageReplyActionIdentifier = "TXNotificationActionIdentifierPrivateMessageReply"

private let notificationControllerLogger = Logger(
	subsystem: Bundle.main.bundleIdentifier ?? "Glasstual",
	category: "NotificationController"
)

@objc(TLONotificationController)
@MainActor
public final class NotificationController: NSObject, UNUserNotificationCenterDelegate {
	@objc public var areNotificationsDisabled = false

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
		if TPCPreferences.onboardingCompleted() {
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
			title: LocalizedKey("Prompts[qpv-go]"),
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
			title: LocalizedKey("Notifications[3t4-kl]"),
			options: [],
			textInputButtonTitle: LocalizedKey("Notifications[bhn-uo]"),
			textInputPlaceholder: LocalizedKey("Notifications[do4-2e]")
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
		let mainWindow = NSObject.masterController().mainWindow

		guard let client = mainWindow.selectedClient else {
			return
		}

		dismissNotifications(for: mainWindow.selectedChannel, on: client)
	}

	@objc(titleForEvent:)
	public func title(forEvent event: TXNotificationType) -> String {
		switch event {
		case .addressBookMatch:
			return LocalizedKey("Notifications[kx3-xk]")
		case .channelMessage:
			return LocalizedKey("Notifications[qnz-k4]")
		case .channelNotice:
			return LocalizedKey("Notifications[vuq-jp]")
		case .connect:
			return LocalizedKey("Notifications[4lr-ej]")
		case .disconnect:
			return LocalizedKey("Notifications[wjv-yb]")
		case .invite:
			return LocalizedKey("Notifications[eiu-8q]")
		case .kick:
			return LocalizedKey("Notifications[2nk-lg]")
		case .newPrivateMessage:
			return LocalizedKey("Notifications[5yi-gu]")
		case .privateMessage:
			return LocalizedKey("Notifications[00b-nx]")
		case .privateNotice:
			return LocalizedKey("Notifications[nhz-io]")
		case .highlight:
			return LocalizedKey("Notifications[cs4-x9]")
		case .fileTransferSendSuccessful:
			return LocalizedKey("Notifications[0x2-3h]")
		case .fileTransferReceiveSuccessful:
			return LocalizedKey("Notifications[qle-7v]")
		case .fileTransferSendFailed:
			return LocalizedKey("Notifications[sc0-1n]")
		case .fileTransferReceiveFailed:
			return LocalizedKey("Notifications[we9-1b]")
		case .fileTransferReceiveRequested:
			return LocalizedKey("Notifications[st5-0n]")
		case .userJoined:
			return LocalizedKey("Notifications[25q-af]")
		case .userParted:
			return LocalizedKey("Notifications[k3s-by]")
		case .userDisconnected:
			return LocalizedKey("Notifications[0fo-bt]")
		@unknown default:
			return ""
		}
	}

	@objc(notify:title:description:userInfo:)
	public func notify(
		_ eventType: TXNotificationType,
		title eventTitle: String?,
		description eventDescription: String?,
		userInfo eventContext: [String: Any]?
	) {
		var title = eventTitle
		var body = eventDescription

		switch eventType {
		case .highlight:
			title = LocalizedKey("Notifications[qka-f3]", title ?? "")
		case .newPrivateMessage:
			title = LocalizedKey("Notifications[ltn-hf]")
		case .channelMessage:
			title = LocalizedKey("Notifications[ep5-de]", title ?? "")
		case .channelNotice:
			title = LocalizedKey("Notifications[chi-km]", title ?? "")
		case .privateMessage:
			title = LocalizedKey("Notifications[69i-dy]")
		case .privateNotice:
			title = LocalizedKey("Notifications[7hn-dg]")
		case .kick:
			title = LocalizedKey("Notifications[u30-ia]", title ?? "")
		case .invite:
			title = LocalizedKey("Notifications[g4s-cq]", title ?? "")
		case .connect:
			title = LocalizedKey("Notifications[mo1-vn]", title ?? "")
			body = LocalizedKey("Notifications[88k-kl]")
		case .disconnect:
			title = LocalizedKey("Notifications[7xe-ig]", title ?? "")
			body = LocalizedKey("Notifications[bif-2c]")
		case .addressBookMatch:
			title = LocalizedKey("Notifications[niq-32]")
		case .fileTransferSendSuccessful:
			title = LocalizedKey("Notifications[l5y-sx]", title ?? "")
		case .fileTransferReceiveSuccessful:
			title = LocalizedKey("Notifications[hc9-7n]", title ?? "")
		case .fileTransferSendFailed:
			title = LocalizedKey("Notifications[het-vh]", title ?? "")
		case .fileTransferReceiveFailed:
			title = LocalizedKey("Notifications[hm4-ze]", title ?? "")
		case .fileTransferReceiveRequested:
			title = LocalizedKey("Notifications[nqz-7v]", title ?? "")
		case .userJoined:
			title = LocalizedKey("Notifications[keq-ts]", title ?? "")
		case .userParted:
			title = LocalizedKey("Notifications[im4-p0]", title ?? "")
		case .userDisconnected:
			title = LocalizedKey("Notifications[20x-32]", title ?? "")
		@unknown default:
			break
		}

		if TPCPreferences.removeAllFormatting() == false, let currentBody = body {
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

		let clientId = eventContext?[TXNotificationUserInfoClientIdentifierKey] as? String
		let channelId = eventContext?[TXNotificationUserInfoChannelIdentifierKey] as? String
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

	@objc(threadIdentifierForClient:channel:)
	public class func threadIdentifier(forClient clientIdentifier: String?, channel channelIdentifier: String?)
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
				TXNotificationUserInfoClientIdentifierKey: clientId,
				TXNotificationUserInfoChannelIdentifierKey: channelId,
			]
		} else {
			[TXNotificationUserInfoClientIdentifierKey: clientId]
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
		let identifier =
			notificationIdentifier
				?? Self.notificationIdentifier(title: title, message: message, threadIdentifier: threadIdentifier)

		scheduleNotification(content: content, identifier: identifier)
	}

	@objc(notificationIdentifierWithTitle:message:threadIdentifier:)
	public class func notificationIdentifier(
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

	public nonisolated func userNotificationCenter(
		_: UNUserNotificationCenter,
		openSettingsFor _: UNNotification?
	) {
		Task { @MainActor in
			NSObject.masterController().menuController?.showNotificationPreferences(nil)
		}
	}

	public nonisolated func userNotificationCenter(
		_: UNUserNotificationCenter,
		willPresent _: UNNotification,
		withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
	) {
		completionHandler([.list, .banner])
	}

	public nonisolated func userNotificationCenter(
		_: UNUserNotificationCenter,
		didReceive response: UNNotificationResponse,
		withCompletionHandler completionHandler: @escaping () -> Void
	) {
		let actionIdentifier = response.actionIdentifier
		let message = (response as? UNTextInputNotificationResponse)?.userText
		let userInfo = response.notification.request.content.userInfo

		let clientId = userInfo[TXNotificationUserInfoClientIdentifierKey] as? String
		let channelId = userInfo[TXNotificationUserInfoChannelIdentifierKey] as? String
		let fileTransferNotificationType = (userInfo as NSDictionary).integer(
			forKey: "fileTransferNotificationType"
		)
		let fileTransferUniqueIdentifier = userInfo["fileTransferUniqueIdentifier"] as? String

		nonisolated(unsafe) let completion = completionHandler

		Task { @MainActor in
			self.notificationResponseReceived(
				actionIdentifier: actionIdentifier,
				clientId: clientId,
				channelId: channelId,
				fileTransferNotificationType: fileTransferNotificationType,
				fileTransferUniqueIdentifier: fileTransferUniqueIdentifier,
				withReplyMessage: message
			)

			completion()
		}
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
	public nonisolated class func isNotification(
		userInfo: [AnyHashable: Any],
		inScopeOfClientIdentifier clientIdentifier: String,
		channelIdentifier: String?
	) -> Bool {
		let clientIdRight = userInfo[TXNotificationUserInfoClientIdentifierKey] as? String
		let channelIdRight = userInfo[TXNotificationUserInfoChannelIdentifierKey] as? String

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
			NSObject.masterController().mainWindow.makeKeyAndOrderFront(nil)
		}

		/* Handle file transfer notifications allowing the user to start a
		 file transfer directly through the notification's action button. */
		if isFileTransferAction {
			TXSharedApplication.sharedFileTransferDialog().show(true, restorePosition: false)

			guard fileTransferNotificationType == TXNotificationType.fileTransferReceiveRequested.rawValue else {
				return
			}

			guard let fileTransferUniqueIdentifier else {
				return
			}

			guard
				let fileTransfer = TXSharedApplication.sharedFileTransferDialog()
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

		let world = NSObject.masterController().world

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
			NSObject.masterController().mainWindow.select(channel)
		} else if let client {
			NSObject.masterController().mainWindow.select(client)
		}

		guard let channel else {
			return
		}

		guard let message, !message.isEmpty else {
			return
		}

		channel.associatedClient?.inputText(message, destination: channel)
	}

	// MARK: - Preferences

	@objc(soundForEvent:inChannel:)
	public func sound(forEvent event: TXNotificationType, in channel: IRCChannel?) -> String? {
		if let channel, let channelValue = channel.config.sound(forEvent: event) {
			return channelValue
		}

		return TPCPreferences.sound(forEvent: event)
	}

	@objc(speakEvent:inChannel:)
	public func speakEvent(_ event: TXNotificationType, in channel: IRCChannel?) -> Bool {
		if let channel {
			let channelValue = channel.config.speakEvent(event)

			if channelValue != .mixed {
				return channelValue == .on
			}
		}

		return TPCPreferences.speakEvent(event)
	}

	@objc(notificationEnabledForEvent:inChannel:)
	public func notificationEnabled(forEvent event: TXNotificationType, in channel: IRCChannel?) -> Bool {
		if let channel {
			let channelValue = channel.config.notificationEnabled(forEvent: event)

			if channelValue != .mixed {
				return channelValue == .on
			}
		}

		return TPCPreferences.notificationEnabled(forEvent: event)
	}

	@objc(disabledWhileAwayForEvent:inChannel:)
	public func disabledWhileAway(forEvent event: TXNotificationType, in channel: IRCChannel?) -> Bool {
		if let channel {
			let channelValue = channel.config.disabledWhileAway(forEvent: event)

			if channelValue != .mixed {
				return channelValue == .on
			}
		}

		return TPCPreferences.disabledWhileAway(forEvent: event)
	}

	@objc(bounceDockIconForEvent:inChannel:)
	public func bounceDockIcon(forEvent event: TXNotificationType, in channel: IRCChannel?) -> Bool {
		if let channel {
			let channelValue = channel.config.bounceDockIcon(forEvent: event)

			if channelValue != .mixed {
				return channelValue == .on
			}
		}

		return TPCPreferences.bounceDockIcon(forEvent: event)
	}

	@objc(bounceDockIconRepeatedlyForEvent:inChannel:)
	public func bounceDockIconRepeatedly(forEvent event: TXNotificationType, in channel: IRCChannel?) -> Bool {
		if let channel {
			let channelValue = channel.config.bounceDockIconRepeatedly(forEvent: event)

			if channelValue != .mixed {
				return channelValue == .on
			}
		}

		return TPCPreferences.bounceDockIconRepeatedly(forEvent: event)
	}
}
