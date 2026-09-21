// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation

@MainActor
extension ServerSession {
	/** Raises one event: the Dock bounce and the notification itself.

	 An event only reaches a person when it was addressed to them and the
	 conversation it happened in is not muted. Everything else is already in
	 the transcript with an unread badge against it. */
	func notifyEvent(
		_ event: UserNotificationEvent,
		lineType: ChatLineKind,
		target: Conversation? = nil,
		nickname: String? = nil,
		text: String? = nil,
		userInfo suppliedUserInfo: UserNotificationPayload? = nil
	) {
		guard nickname.map({ isUserMuted(nickname: $0) }) != true else { return }
		guard UserNotificationPolicy.admits(UserNotificationAdmissionContext(
			event: event,
			isTerminating: isTerminating,
			isCollapsingNetsplit: netsplitCollapse.isCollapsing,
			nicknameIsLocalUser: nickname.map(nicknameIsMyself) ?? false,
			conversationIsMuted: target.map { conversationIsMuted($0, for: event) } ?? false
		)) else { return }

		guard let presenter = environment.services.notifications,
		      presenter.areNotificationsDisabled == false else { return }

		guard UserNotificationPolicy.postsNotification(
			event: event,
			notifiesAboutMentions: environment.settings.notifyAboutMentions,
			postWhileFocused: environment.settings.postNotificationsWhileInFocus,
			mainWindowIsFocused: output.map { window in window.isKeyWindow || window.isMainWindow } == true,
			targetIsSelected: output?.isItemSelected(target) == true
		) else { return }

		guard let content = userNotificationContent(
			for: event,
			lineType: lineType,
			target: target,
			nickname: nickname,
			text: text
		) else { return }

		let payload = suppliedUserInfo ?? UserNotificationPayload(
			sessionIdentifier: uniqueIdentifier,
			conversationIdentifier: target?.uniqueIdentifier,
			directNickname: target?.isDirect == true ? target?.name : nil
		)

		/* Only the first alert of a burst in one conversation interrupts; the
		 ones behind it are added to Notification Center quietly. */
		let alerts = presenter.claimsAlert(inThread: payload.threadIdentifier)

		if alerts {
			presenter.requestUserAttention()
		}

		presenter.post(PendingUserNotification(
			event: event,
			title: content.title,
			subtitle: content.subtitle,
			body: content.body,
			payload: payload,
			alerts: alerts,
			playsSound: alerts && environment.settings.soundIsMuted == false
		))
	}

	/// Whether `conversation` has alerts switched off for this event.
	private func conversationIsMuted(_ conversation: Conversation, for event: UserNotificationEvent) -> Bool {
		if event == .highlight, conversation.config.ignoreHighlights {
			return true
		}

		return conversation.config.pushNotifications == false
	}

	/** What one event's notification says.

	 The title is who or what it is about, the subtitle is where it happened and
	 the body is the detail, the shape Messages and Mail use. */
	private func userNotificationContent(
		for event: UserNotificationEvent,
		lineType: ChatLineKind,
		target: Conversation?,
		nickname: String?,
		text: String?
	) -> UserNotificationContent? {
		switch event {
		case .highlight, .newPrivateMessage, .privateMessage, .privateNotice:
			textUserNotificationContent(
				for: event,
				lineType: lineType,
				target: target,
				nickname: nickname,
				text: text
			)

		case .fileTransferSendSuccessful, .fileTransferReceiveSuccessful, .fileTransferSendFailed,
		     .fileTransferReceiveFailed, .fileTransferReceiveRequested:
			nickname.map {
				UserNotificationContent(title: String(localized: event.title), subtitle: $0, body: text)
			}

		case .addressBookMatch:
			text.map {
				UserNotificationContent(
					title: String(localized: event.title),
					subtitle: networkNameAlt,
					body: $0
				)
			}

		case .kick:
			kickUserNotificationContent(target: target, nickname: nickname, reason: text)

		case .invite:
			inviteUserNotificationContent(nickname: nickname, channelName: text)

		/* Everything else is a room event or a connection change. The transcript
		 and the unread badge carry those; nothing interrupts for them. */
		default:
			nil
		}
	}

	/** Who said it, where, and what they said -- as three fields.

	 A message notification reads like every other one on the system: the
	 nickname in the title, the conversation in the subtitle, the message in the
	 body. An action keeps its composed "nickname does something" body, because
	 there the nickname is part of the sentence. */
	private func textUserNotificationContent(
		for event: UserNotificationEvent,
		lineType: ChatLineKind,
		target: Conversation?,
		nickname: String?,
		text: String?
	) -> UserNotificationContent? {
		guard let nickname, let text else { return nil }

		let location = event == .highlight ? target?.name : nil
		let isAction = lineType == .action || lineType == .actionNoHighlight
		let body = isAction
			? String(localized: .Notifications.bodyActionWithNickname(nickname, text))
			: text

		return UserNotificationContent(
			title: formatNickname(nickname, in: target),
			subtitle: location,
			body: body
		)
	}

	private func kickUserNotificationContent(
		target: Conversation?,
		nickname: String?,
		reason: String?
	) -> UserNotificationContent? {
		guard let nickname, let target else { return nil }

		let body = if let reason, reason.isEmpty == false {
			String(localized: .Notifications.bodyKicked(nickname, reason))
		} else {
			String(localized: .Notifications.bodyKickedWithoutReason(nickname))
		}

		return UserNotificationContent(title: String(localized: .Notifications.typeKicked), subtitle: target.name, body: body)
	}

	private func inviteUserNotificationContent(nickname: String?, channelName: String?) -> UserNotificationContent? {
		guard let nickname, let channelName else { return nil }

		return UserNotificationContent(
			title: String(localized: .Notifications.typeChannelInvitation),
			subtitle: networkNameAlt,
			body: String(localized: .Notifications.bodyInvited(nickname, channelName))
		)
	}
}

/** What one notification says.

 The title is who or what it is about, the subtitle is where it happened and
 the body is the detail. Every event fills the title; the rest is what it has. */
struct UserNotificationContent {
	var title: String
	var subtitle: String?
	var body: String?
}
