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
import os
import UserNotifications

/// What the notification center asks the controller, and what the person does
/// with a delivered notification.
extension NotificationController: UNUserNotificationCenterDelegate {
	func userNotificationCenter(
		_: UNUserNotificationCenter,
		openSettingsFor _: UNNotification?
	) {
		AppServices.delegate.menuController?.actionCoordinator.showNotificationPreferences(nil)
	}

	func userNotificationCenter(
		_: UNUserNotificationCenter,
		willPresent _: UNNotification
	) async -> UNNotificationPresentationOptions {
		Self.presentationOptions(notificationsAreDisabled: areNotificationsDisabled)
	}

	/** How a notification that arrives while Glasstual is frontmost is shown.

	 `.sound` is part of the answer. Without it the system shows the banner and
	 drops the sound the notification carries, which is every sound for an event
	 raised while the application is in front. */
	static func presentationOptions(notificationsAreDisabled: Bool) -> UNNotificationPresentationOptions {
		notificationsAreDisabled ? [] : [.list, .banner, .sound]
	}

	func userNotificationCenter(
		_: UNUserNotificationCenter,
		didReceive response: UNNotificationResponse
	) async {
		notificationResponseReceived(
			actionIdentifier: response.actionIdentifier,
			payload: NotificationPayload(userInfo: response.notification.request.content.userInfo),
			replyMessage: (response as? UNTextInputNotificationResponse)?.userText
		)
	}

	func notificationResponseReceived(
		actionIdentifier: String,
		payload: NotificationPayload,
		replyMessage: String?
	) {
		if actionIdentifier == UNNotificationDismissActionIdentifier {
			return
		}

		if let identifier = payload.fileTransferIdentifier {
			fileTransferResponseReceived(
				actionIdentifier: actionIdentifier,
				identifier: identifier,
				payload: payload
			)

			return
		}

		guard let world = AppServices.world else {
			return
		}

		/* A reply is answered where it was typed. Raising the main window over it,
		 or moving its selection to the query, is what the person did not ask for. */
		if actionIdentifier == NotificationCategory.Action.replyToPrivateMessage.rawValue {
			sendReply(replyMessage, for: payload, in: world)
			return
		}

		NSApp.activate()
		AppServices.delegate.mainWindow.makeKeyAndOrderFront(nil)

		guard let clientId = payload.clientIdentifier else {
			return
		}

		guard let channelId = payload.channelIdentifier else {
			if let client = world.findClient(withId: clientId) {
				AppServices.delegate.mainWindow.select(client)
			}

			return
		}

		guard let channel = world.findChannel(withId: channelId, onClientWithId: clientId) else {
			return
		}

		AppServices.delegate.mainWindow.select(channel)
	}

	private func sendReply(_ replyMessage: String?, for payload: NotificationPayload, in world: ClientDirectory) {
		guard let replyMessage, replyMessage.isEmpty == false else {
			return
		}

		guard let destination = Self.replyDestination(for: payload, in: world),
		      let client = destination.associatedClient
		else {
			notificationControllerLogger.error("Dropped a notification reply whose conversation no longer exists")
			return
		}

		client.inputText(replyMessage, destination: destination)
	}

	/** The conversation a reply typed into a notification goes to.

	 The one the notification came from, when it is still open. A private
	 message closed since the notification arrived opens again under the
	 nickname the notification carries: the reply used to go nowhere, without a
	 word, once the query was gone. `nil` when the connection is gone as well. */
	static func replyDestination(for payload: NotificationPayload, in world: ClientDirectory) -> Channel? {
		guard let clientId = payload.clientIdentifier else {
			return nil
		}

		if let channelId = payload.channelIdentifier,
		   let channel = world.findChannel(withId: channelId, onClientWithId: clientId)
		{
			return channel
		}

		guard let queryName = payload.queryName, let client = world.findClient(withId: clientId) else {
			return nil
		}

		return client.findChannelOrCreate(queryName, isPrivateMessage: true)
	}

	private func fileTransferResponseReceived(
		actionIdentifier: String,
		identifier: String,
		payload: NotificationPayload
	) {
		let center = AppServices.fileTransfers
		let clientIdentifier = payload.clientIdentifier

		if actionIdentifier == NotificationCategory.Action.declineFileTransfer.rawValue {
			center.declineNotification(for: identifier, clientIdentifier: clientIdentifier)
			return
		}

		let accepts = actionIdentifier == NotificationCategory.Action.acceptFileTransfer.rawValue

		guard actionIdentifier == UNNotificationDefaultActionIdentifier || accepts else {
			return
		}

		let accept = accepts
			&& payload.fileTransferEventRawValue == Int(NotificationEvent.fileTransferReceiveRequested.rawValue)
		/* The transfer may have been cleared before the click arrived. The click
		 still asked for the transfer list, so the list still opens. */
		_ = center.respondToNotification(for: identifier, clientIdentifier: clientIdentifier, accept: accept)
		NSApp.activate()
		center.present()
	}
}
