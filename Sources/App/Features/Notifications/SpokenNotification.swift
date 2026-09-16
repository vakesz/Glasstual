/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 *********************************************************************** */

import Foundation

/** A queued speech request. Identifiers rather than object references: the
 synthesizer only needs to know which client a queued item belongs to, and
 holding weak references to main-actor models across the queue turned an
 ordinary deallocation into a crash. */
struct SpokenNotification: Sendable {
	let clientIdentifier: String?
	let channelIdentifier: String?
	let nickname: String?
	let text: String?
	let lineType: LogLineType
	let notificationType: NotificationEvent

	/** The text the synthesizer speaks. Formatting reads main-actor client state,
	 so the producer fills it in before the notification is queued. */
	var spokenText: String?

	@MainActor
	init(
		notificationType: NotificationEvent,
		lineType: LogLineType,
		target: ChatItem?,
		nickname: String?,
		text: String?
	) {
		self.notificationType = notificationType
		self.lineType = lineType

		if target?.isClient == true {
			clientIdentifier = target?.uniqueIdentifier
			channelIdentifier = nil
		} else {
			clientIdentifier = target?.associatedClient?.uniqueIdentifier
			channelIdentifier = (target as? Channel)?.uniqueIdentifier
		}

		self.nickname = nickname
		self.text = text
	}
}

/** What the synthesizer's queue holds. */
enum SpeechItem: Sendable {
	case text(String)
	case notification(SpokenNotification)

	var isNotification: Bool {
		if case .notification = self {
			return true
		}
		return false
	}

	var spokenText: String? {
		switch self {
		case let .text(text):
			text
		case let .notification(notification):
			notification.spokenText
		}
	}

	func belongs(to clientIdentifier: String) -> Bool {
		switch self {
		case .text:
			false
		case let .notification(notification):
			notification.clientIdentifier == clientIdentifier
		}
	}
}
