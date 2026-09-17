// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2018 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/** Something that happened which a person may want to hear about.

 The raw values are stored with delivered notifications, so they stay as they
 are. */
nonisolated enum NotificationEvent: UInt, CaseIterable, Sendable {
	case highlight = 1000
	case newPrivateMessage
	case channelMessage
	case channelNotice
	case privateMessage
	case privateNotice
	case kick
	case invite
	case connect
	case disconnect
	case addressBookMatch
	case fileTransferSendSuccessful
	case fileTransferReceiveSuccessful
	case fileTransferSendFailed
	case fileTransferReceiveFailed
	case fileTransferReceiveRequested
	case userJoined
	case userParted
	case userDisconnected

	/** Whether the event is addressed to the person rather than to the room.

	 Only these notify. A channel filling up with messages, someone joining it
	 and a connection coming back are what the transcript and the unread badge
	 are for; interrupting for them is what nineteen switches used to be needed
	 to turn off. */
	var isAddressedToLocalUser: Bool {
		switch self {
		case .highlight, .newPrivateMessage, .privateMessage, .privateNotice,
		     .kick, .invite, .addressBookMatch:
			true
		default:
			false
		}
	}

	/// A file transfer asks a question only a notification can put in front of
	/// the person, so it notifies whatever else is switched off.
	var isFileTransfer: Bool {
		switch self {
		case .fileTransferSendSuccessful, .fileTransferReceiveSuccessful, .fileTransferSendFailed,
		     .fileTransferReceiveFailed, .fileTransferReceiveRequested:
			true
		default:
			false
		}
	}

	/** What the event is called.

	 A notification that is not someone speaking carries this as its title.
	 Titles used to be a second family of "<Category>: <subject>" strings that
	 said in the title what the subtitle already said. */
	var title: LocalizedStringResource {
		switch self {
		case .addressBookMatch: .Notifications.typeAddressBook
		case .channelMessage: .Notifications.typeChannelMessage
		case .channelNotice: .Notifications.typeChannelNotice
		case .connect: .Notifications.typeConnected
		case .disconnect: .Notifications.typeDisconnected
		case .invite: .Notifications.typeChannelInvitation
		case .kick: .Notifications.typeKicked
		case .newPrivateMessage: .Notifications.typeNewPrivateMessage
		case .privateMessage: .Notifications.typePrivateMessage
		case .privateNotice: .Notifications.typePrivateNotice
		case .highlight: .Notifications.typeHighlight
		case .fileTransferSendSuccessful: .Notifications.typeFileTransferSendSuccessful
		case .fileTransferReceiveSuccessful: .Notifications.typeFileTransferReceiveSuccessful
		case .fileTransferSendFailed: .Notifications.typeFileTransferSendFailed
		case .fileTransferReceiveFailed: .Notifications.typeFileTransferReceiveFailed
		case .fileTransferReceiveRequested: .Notifications.typeFileTransferRequest
		case .userJoined: .Notifications.typeUserJoined
		case .userParted: .Notifications.typeUserParted
		case .userDisconnected: .Notifications.typeUserDisconnected
		}
	}

	/// The sentence under a file transfer notification's heading.
	func fileTransferBody(filename: String, byteCount: UInt64) -> String? {
		let size = LocalizedByteCount.formatted(byteCount)

		return switch self {
		case .fileTransferSendSuccessful:
			String(localized: .Notifications.bodyFileTransferSendSuccessful(filename, size))
		case .fileTransferReceiveSuccessful:
			String(localized: .Notifications.bodyFileTransferReceiveSuccessful(filename, size))
		case .fileTransferSendFailed:
			String(localized: .Notifications.bodyFileTransferSendFailed(filename))
		case .fileTransferReceiveFailed:
			String(localized: .Notifications.bodyFileTransferReceiveFailed(filename))
		case .fileTransferReceiveRequested:
			String(localized: .Notifications.bodyFileTransferRequest(filename, size))
		default:
			nil
		}
	}
}
