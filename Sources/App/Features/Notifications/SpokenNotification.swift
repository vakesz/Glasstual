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
public struct SpokenNotification: Sendable {
	public let clientIdentifier: String?
	public let channelIdentifier: String?
	public let nickname: String?
	public let text: String?
	public let lineType: TVCLogLineType
	public let notificationType: TXNotificationType

	/** The text the synthesizer speaks. Formatting reads main-actor client state,
	 so the producer fills it in before the notification is queued. */
	public var spokenText: String?

	@MainActor
	public init(
		notificationType: TXNotificationType,
		lineType: TVCLogLineType,
		target: IRCTreeItem?,
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
			channelIdentifier = (target as? IRCChannel)?.uniqueIdentifier
		}

		self.nickname = nickname
		self.text = text
	}
}

/** What the synthesizer's queue holds. */
public enum SpeechItem: Sendable {
	case text(String)
	case notification(SpokenNotification)

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
