// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

struct UserNotificationAdmissionContext {
	let event: UserNotificationEvent
	let isTerminating: Bool
	let isCollapsingNetsplit: Bool
	let nicknameIsLocalUser: Bool
	/// The conversation the event happened in has alerts switched off.
	let conversationIsMuted: Bool
}

/** Which events reach the person, and how loudly.

 Notifications answer four questions and no more: is this conversation muted,
 does the person want to hear about mentions, may a sound play, and may the
 Dock badge count. Everything here is a pure function of those, so the rules
 are testable without a notification centre. */
enum UserNotificationPolicy {
	static func isTextEvent(_ event: UserNotificationEvent) -> Bool {
		switch event {
		case .highlight, .newPrivateMessage, .channelMessage, .channelNotice, .privateMessage, .privateNotice:
			true
		default:
			false
		}
	}

	/// Whether an event is worth answering at all, before anything is built for
	/// it. A muted conversation's unread badge is raised by `setUnreadState`,
	/// which is why a refusal here needs no shade of its own.
	static func admits(_ context: UserNotificationAdmissionContext) -> Bool {
		if context.isTerminating {
			return false
		}

		if context.isCollapsingNetsplit,
		   context.event == .userJoined || context.event == .userDisconnected
		{
			return false
		}

		if isTextEvent(context.event), context.nicknameIsLocalUser {
			return false
		}

		/* A file transfer belongs to no conversation, so muting one cannot
		 silence the question it asks. */
		if context.conversationIsMuted, context.event.isFileTransfer == false {
			return false
		}

		return true
	}

	/** Whether the event posts a notification.

	 A file transfer always does: accepting or declining it is the notification's
	 own question. Everything else has to be addressed to the person, and the
	 person has to have asked to hear about those. A conversation the person is
	 reading in a window they are looking at needs no banner for what is already
	 on screen. */
	static func postsNotification(
		event: UserNotificationEvent,
		notifiesAboutMentions: Bool,
		postWhileFocused: Bool,
		mainWindowIsFocused: Bool,
		targetIsSelected: Bool
	) -> Bool {
		if event.isFileTransfer {
			return true
		}

		guard event.isAddressedToLocalUser, notifiesAboutMentions else {
			return false
		}

		if mainWindowIsFocused, targetIsSelected || postWhileFocused == false {
			return false
		}

		return true
	}
}
