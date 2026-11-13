// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
import CocoaExtensions
import os
import UserNotifications

/// What the notification center asks the controller, and what the person does
/// with a delivered notification.
extension UserNotificationController: UNUserNotificationCenterDelegate {
	func userNotificationCenter(
		_: UNUserNotificationCenter,
		openSettingsFor _: UNNotification?
	) {
		AppServices.delegate.menuController?.showNotificationSettings()
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
			payload: UserNotificationPayload(userInfo: response.notification.request.content.userInfo),
			replyMessage: (response as? UNTextInputNotificationResponse)?.userText
		)
	}

	func notificationResponseReceived(
		actionIdentifier: String,
		payload: UserNotificationPayload,
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

		guard let chatSession = AppServices.chatSession else {
			return
		}

		/* Marking read is answered where it was chosen too: nothing is raised
		 and the selection stays where it is. */
		if actionIdentifier == UserNotificationCategory.Action.markConversationAsRead.rawValue {
			markConversationAsRead(for: payload, in: chatSession)
			return
		}

		/* A reply is answered where it was typed. Raising the main window over it,
		 or moving its selection to that conversation, is what the person did not
		 ask for. */
		if actionIdentifier == UserNotificationCategory.Action.replyToPrivateMessage.rawValue {
			sendReply(replyMessage, for: payload, in: chatSession)
			return
		}

		ApplicationForeground.bringForward(AppServices.delegate.mainWindow)

		guard let sessionId = payload.sessionIdentifier else {
			return
		}

		guard let conversationId = payload.conversationIdentifier else {
			if let session = chatSession.findSession(withId: sessionId) {
				AppServices.delegate.mainWindow.select(session)
			}

			return
		}

		guard let conversation = chatSession.findConversation(withId: conversationId, onSessionWithId: sessionId) else {
			return
		}

		AppServices.delegate.mainWindow.select(conversation)
	}

	private func markConversationAsRead(for payload: UserNotificationPayload, in chatSession: ChatSession) {
		guard let sessionId = payload.sessionIdentifier,
		      let conversationId = payload.conversationIdentifier,
		      let conversation = chatSession.findConversation(withId: conversationId, onSessionWithId: sessionId)
		else {
			return
		}

		conversation.resetState()
		DockIcon.updateDockIcon()
	}

	private func sendReply(_ replyMessage: String?, for payload: UserNotificationPayload, in chatSession: ChatSession) {
		guard let replyMessage, replyMessage.isEmpty == false else {
			return
		}

		guard let destination = Self.replyDestination(for: payload, in: chatSession),
		      let session = destination.associatedSession
		else {
			userNotificationControllerLogger.error("Dropped a notification reply whose conversation no longer exists")
			return
		}

		session.inputText(replyMessage, destination: destination)
	}

	/** The conversation a reply typed into a notification goes to.

	 The one the notification came from, when it is still open. A one-to-one
	 conversation closed since the notification arrived opens again under the
	 nickname the notification carries: the reply used to go nowhere, without a
	 word, once that conversation was gone. `nil` when the connection is gone as
	 well. */
	static func replyDestination(for payload: UserNotificationPayload, in chatSession: ChatSession) -> Conversation? {
		guard let sessionId = payload.sessionIdentifier else {
			return nil
		}

		if let conversationId = payload.conversationIdentifier,
		   let conversation = chatSession.findConversation(withId: conversationId, onSessionWithId: sessionId)
		{
			return conversation
		}

		guard let directNickname = payload.directNickname,
		      let session = chatSession.findSession(withId: sessionId)
		else {
			return nil
		}

		return session.findConversationOrCreate(directNickname, isDirect: true)
	}

	private func fileTransferResponseReceived(
		actionIdentifier: String,
		identifier: String,
		payload: UserNotificationPayload
	) {
		let center = AppServices.fileTransfers
		let sessionIdentifier = payload.sessionIdentifier

		if actionIdentifier == UserNotificationCategory.Action.declineFileTransfer.rawValue {
			center.declineNotification(for: identifier, sessionIdentifier: sessionIdentifier)
			return
		}

		let accepts = actionIdentifier == UserNotificationCategory.Action.acceptFileTransfer.rawValue

		guard actionIdentifier == UNNotificationDefaultActionIdentifier || accepts else {
			return
		}

		let accept = accepts
			&& payload.fileTransferEventRawValue == Int(UserNotificationEvent.fileTransferReceiveRequested.rawValue)
		/* The transfer may have been cleared before the click arrived. The click
		 still asked for the transfer list, so the list still opens. */
		_ = center.respondToNotification(for: identifier, sessionIdentifier: sessionIdentifier, accept: accept)
		ApplicationForeground.activate()
		center.present()
	}
}
