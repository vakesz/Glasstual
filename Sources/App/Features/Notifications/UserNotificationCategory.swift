// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
import UserNotifications

/** The notification categories Glasstual registers, one per kind of
 notification it posts.

 A category names the actions the system offers on a notification. It also
 names the text the system shows in place of the notification when the person
 hides previews, and the summary under a stack of notifications from one
 thread. The raw values are stored with every delivered notification: a
 notification already in Notification Centre when one of them changes keeps
 naming a category the application no longer registers, and so loses its
 actions. */
enum UserNotificationCategory: String, CaseIterable {
	/// Messages, mentions, joins and connection changes: every event with no
	/// actions of its own.
	case activity = "GlasstualNotificationCategoryActivity"
	case fileTransfer = "GlasstualNotificationCategoryFileTransfer"
	case privateMessage = "GlasstualNotificationCategoryPrivateMessage"

	/// The actions a notification offers, by the identifier the system reports
	/// back when the person picks one.
	enum Action: String {
		case acceptFileTransfer = "GlasstualNotificationActionAcceptFileTransfer"
		case declineFileTransfer = "GlasstualNotificationActionDeclineFileTransfer"
		case replyToPrivateMessage = "GlasstualNotificationActionReplyToPrivateMessage"
	}

	init(event: UserNotificationEvent) {
		switch event {
		case .fileTransferReceiveRequested: self = .fileTransfer
		case .newPrivateMessage, .privateMessage: self = .privateMessage
		default: self = .activity
		}
	}

	var userNotificationCategory: UNNotificationCategory {
		UNNotificationCategory(
			identifier: rawValue,
			actions: actions,
			intentIdentifiers: [],
			hiddenPreviewsBodyPlaceholder: hiddenPreviewsBodyPlaceholder,
			categorySummaryFormat: summaryFormat,
			options: [.customDismissAction]
		)
	}

	private var actions: [UNNotificationAction] {
		switch self {
		case .activity:
			[]
		case .fileTransfer:
			[
				UNNotificationAction(
					identifier: Action.acceptFileTransfer.rawValue,
					title: PromptStrings.Action.accept,
					options: [.foreground]
				),
				/* Declining from the notification is the other answer the request
					asks for. Without it, the only way to say no was to open the
					transfer list and stop the transfer there. */
				UNNotificationAction(
					identifier: Action.declineFileTransfer.rawValue,
					title: String(localized: .Notifications.fileTransferDeclineAction),
					options: [.destructive]
				),
			]
		case .privateMessage:
			[
				UNTextInputNotificationAction(
					identifier: Action.replyToPrivateMessage.rawValue,
					title: String(localized: .Notifications.replyActionTitle),
					options: [],
					textInputButtonTitle: String(localized: .Notifications.replySendButton),
					textInputPlaceholder: String(localized: .Notifications.replyPlaceholder)
				),
			]
		}
	}

	/// What the system shows instead of the title and body when the person
	/// hides notification previews.
	private var hiddenPreviewsBodyPlaceholder: String {
		switch self {
		case .activity: String(localized: .Notifications.hiddenPreviewActivity)
		case .fileTransfer: String(localized: .Notifications.hiddenPreviewFileTransfer)
		case .privateMessage: String(localized: .Notifications.hiddenPreviewPrivateMessage)
		}
	}

	/// The summary under a collapsed stack. The system replaces `%u` with how
	/// many notifications the stack holds.
	private var summaryFormat: String {
		/* The system counts the stack and puts the number where `%u` is, so the
		 format has to reach it with `%u` still in it. The catalog entries take
		 the placeholder as their argument for that reason. */
		let count = "%u"

		return switch self {
		case .activity: String(localized: .Notifications.summaryActivity(count))
		case .fileTransfer: String(localized: .Notifications.summaryFileTransfers(count))
		case .privateMessage: String(localized: .Notifications.summaryPrivateMessages(count))
		}
	}
}
