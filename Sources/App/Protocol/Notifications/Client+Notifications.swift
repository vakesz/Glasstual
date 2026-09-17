// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
import CocoaExtensions
import Foundation

@MainActor
extension Client {
	/** Raises one event: the Dock bounce and the notification itself.

	 An event only reaches a person when it was addressed to them and the
	 conversation it happened in is not muted. Everything else is already in
	 the transcript with an unread badge against it. */
	func notifyEvent(
		_ event: NotificationEvent,
		lineType: LogLineType,
		target: Channel? = nil,
		nickname: String? = nil,
		text: String? = nil,
		userInfo suppliedUserInfo: NotificationPayload? = nil
	) {
		let admission = NotificationPolicy.admission(for: NotificationAdmissionContext(
			event: event,
			isTerminating: isTerminating,
			isCollapsingNetsplit: collapsedNetsplitBatch != nil,
			nicknameIsLocalUser: nickname.map(nicknameIsMyself) ?? false,
			conversationIsMuted: target.map { conversationIsMuted($0, for: event) } ?? false
		))

		guard admission == .proceed else { return }

		let presenter: any ClientNotificationPresenting = AppServices.notifications

		guard presenter.areNotificationsDisabled == false else { return }

		guard NotificationPolicy.postsNotification(
			event: event,
			notifiesAboutMentions: Preferences.Notifications.notifyAboutMentions.value,
			postWhileFocused: Preferences.Notifications.postWhileInFocus.value,
			mainWindowIsFocused: AppServices.delegate.mainWindow?.isInactive == false,
			targetIsSelected: isSelected(target)
		) else { return }

		guard let content = notificationContent(
			for: event,
			lineType: lineType,
			target: target,
			nickname: nickname,
			text: text
		) else { return }

		let payload = suppliedUserInfo ?? NotificationPayload(
			clientIdentifier: uniqueIdentifier,
			channelIdentifier: target?.uniqueIdentifier,
			queryName: target?.isPrivateMessage == true ? target?.name : nil
		)

		/* Only the first alert of a burst in one conversation interrupts; the
		 ones behind it are added to Notification Center quietly. */
		let alerts = presenter.claimsAlert(inThread: payload.threadIdentifier)

		if alerts {
			NSApp.requestUserAttention(.informationalRequest)
		}

		presenter.post(PendingNotification(
			event: event,
			title: content.title,
			subtitle: content.subtitle,
			body: content.body,
			payload: payload,
			alerts: alerts,
			playsSound: alerts && Preferences.Notifications.soundIsMuted.value == false
		))
	}

	/// Whether `channel` has alerts switched off for this event.
	private func conversationIsMuted(_ channel: Channel, for event: NotificationEvent) -> Bool {
		if event == .highlight, channel.config.ignoreHighlights {
			return true
		}

		return channel.config.pushNotifications == false
	}

	private func isSelected(_ channel: Channel?) -> Bool {
		guard let channel else { return false }
		return AppServices.delegate.mainWindow?.isItemSelected(channel) ?? false
	}

	/** What one event's notification says.

	 The title is who or what it is about, the subtitle is where it happened and
	 the body is the detail, the shape Messages and Mail use. */
	private func notificationContent(
		for event: NotificationEvent,
		lineType: LogLineType,
		target: Channel?,
		nickname: String?,
		text: String?
	) -> NotificationContent? {
		switch event {
		case .highlight, .newPrivateMessage, .privateMessage, .privateNotice:
			textNotificationContent(
				for: event,
				lineType: lineType,
				target: target,
				nickname: nickname,
				text: text
			)

		case .fileTransferSendSuccessful, .fileTransferReceiveSuccessful, .fileTransferSendFailed,
		     .fileTransferReceiveFailed, .fileTransferReceiveRequested:
			nickname.map {
				NotificationContent(title: String(localized: event.title), subtitle: $0, body: text)
			}

		case .addressBookMatch:
			text.map {
				NotificationContent(
					title: String(localized: event.title),
					subtitle: networkNameAlt,
					body: $0
				)
			}

		case .kick:
			kickNotificationContent(target: target, nickname: nickname, reason: text)

		case .invite:
			inviteNotificationContent(nickname: nickname, channelName: text)

		/* Everything else is a room event or a connection change. The transcript
		 and the unread badge carry those; nothing interrupts for them. */
		default:
			nil
		}
	}

	/** Who said it, where, and what they said -- as three fields.

	 A message notification reads like every other one on the system: the
	 nickname in the title, the channel in the subtitle, the message in the
	 body. An action keeps its composed "nickname does something" body, because
	 there the nickname is part of the sentence. */
	private func textNotificationContent(
		for event: NotificationEvent,
		lineType: LogLineType,
		target: Channel?,
		nickname: String?,
		text: String?
	) -> NotificationContent? {
		guard let nickname, let text else { return nil }

		let location = event == .highlight ? target?.name : nil
		let isAction = lineType == .action || lineType == .actionNoHighlight
		let body = isAction
			? String(localized: .Notifications.bodyActionWithNickname(nickname, text))
			: text

		return NotificationContent(
			title: formatNickname(nickname, in: target),
			subtitle: location,
			body: body
		)
	}

	private func kickNotificationContent(
		target: Channel?,
		nickname: String?,
		reason: String?
	) -> NotificationContent? {
		guard let nickname, let target else { return nil }

		let body = if let reason, reason.isEmpty == false {
			String(localized: .Notifications.bodyKicked(nickname, reason))
		} else {
			String(localized: .Notifications.bodyKickedWithoutReason(nickname))
		}

		return NotificationContent(title: String(localized: .Notifications.typeKicked), subtitle: target.name, body: body)
	}

	private func inviteNotificationContent(nickname: String?, channelName: String?) -> NotificationContent? {
		guard let nickname, let channelName else { return nil }

		return NotificationContent(
			title: String(localized: .Notifications.typeChannelInvitation),
			subtitle: networkNameAlt,
			body: String(localized: .Notifications.bodyInvited(nickname, channelName))
		)
	}
}

/** What one notification says.

 The title is who or what it is about, the subtitle is where it happened and
 the body is the detail. Every event fills the title; the rest is what it has. */
struct NotificationContent {
	var title: String
	var subtitle: String?
	var body: String?
}
