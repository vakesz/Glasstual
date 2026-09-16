/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
 * Copyright (c) 2010 - 2018 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 *
 *  * Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 *  * Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 *  * Neither the name of Textual, "Codeux Software, LLC", nor the
 *    names of its contributors may be used to endorse or promote products
 *    derived from this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED. IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
 * FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
 * OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
 * LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
 * OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
 * SUCH DAMAGE.
 *
 *********************************************************************** */

import Foundation

/** Something that happened which a person may want to hear about.

 The raw values are stored with delivered notifications, so they stay as they
 are. */
nonisolated enum NotificationEvent: UInt, CaseIterable, Sendable { // nonisolated: value
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
