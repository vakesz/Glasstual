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

nonisolated enum NotificationStrings { // nonisolated: value
	static var replyActionTitle: String {
		String(localized: .Notifications.replyActionTitle)
	}

	static var replyPlaceholder: String {
		String(localized: .Notifications.replyPlaceholder)
	}

	static var replySendButtonTitle: String {
		String(localized: .Notifications.replySendButton)
	}

	static func messageBody(formattedNickname: String, text: String) -> String {
		String(localized: .Notifications.bodyMessageWithNickname(formattedNickname, text))
	}

	static func actionBody(nickname: String, text: String) -> String {
		String(localized: .Notifications.bodyActionWithNickname(nickname, text))
	}

	/** What one notification event is called.

	 The notification settings table names its rows with this, and a
	 notification that is not someone speaking carries it as its title: the two
	 are the same phrase, so they are the same entry. Titles used to be a second
	 family of "<Category>: <subject>" strings that repeated in the title what
	 the subtitle already said. */
	static func eventTypeTitle(for event: NotificationEvent) -> String {
		switch event {
		case .addressBookMatch:
			String(localized: .Notifications.typeAddressBook)
		case .channelMessage:
			String(localized: .Notifications.typeChannelMessage)
		case .channelNotice:
			String(localized: .Notifications.typeChannelNotice)
		case .connect:
			String(localized: .Notifications.typeConnected)
		case .disconnect:
			String(localized: .Notifications.typeDisconnected)
		case .invite:
			String(localized: .Notifications.typeChannelInvitation)
		case .kick:
			String(localized: .Notifications.typeKicked)
		case .newPrivateMessage:
			String(localized: .Notifications.typeNewPrivateMessage)
		case .privateMessage:
			String(localized: .Notifications.typePrivateMessage)
		case .privateNotice:
			String(localized: .Notifications.typePrivateNotice)
		case .highlight:
			String(localized: .Notifications.typeHighlight)
		case .fileTransferSendSuccessful:
			String(localized: .Notifications.typeFileTransferSendSuccessful)
		case .fileTransferReceiveSuccessful:
			String(localized: .Notifications.typeFileTransferReceiveSuccessful)
		case .fileTransferSendFailed:
			String(localized: .Notifications.typeFileTransferSendFailed)
		case .fileTransferReceiveFailed:
			String(localized: .Notifications.typeFileTransferReceiveFailed)
		case .fileTransferReceiveRequested:
			String(localized: .Notifications.typeFileTransferRequest)
		case .userJoined:
			String(localized: .Notifications.typeUserJoined)
		case .userParted:
			String(localized: .Notifications.typeUserParted)
		case .userDisconnected:
			String(localized: .Notifications.typeUserDisconnected)
		}
	}

	enum Spoken {
		/** One spoken sentence for a channel message, notice or highlight.

		 Which parts a sentence names is the person's choice, so there is an
		 entry per shape rather than a label, a channel, a nickname and a comma
		 concatenated in code: a translator cannot reorder or inflect fragments
		 that Swift glues together in English word order. */
		static func channelEvent(
			_ event: NotificationEvent,
			channelName: String?,
			nickname: String?,
			text: String
		) -> String {
			switch event {
			case .highlight: highlight(channelName: channelName, nickname: nickname, text: text)
			case .channelNotice: channelNotice(channelName: channelName, nickname: nickname, text: text)
			default: channelMessage(channelName: channelName, nickname: nickname, text: text)
			}
		}

		/// A highlight in a private message always names who it came from.
		static func privateHighlight(from nickname: String, text: String) -> String {
			String(localized: .Notifications.spokenHighlightInPrivateMessageFromUser(nickname, text))
		}

		private static func highlight(channelName: String?, nickname: String?, text: String) -> String {
			switch (channelName, nickname) {
			case let (.some(channel), .some(nickname)):
				String(localized: .Notifications.spokenHighlightInChannelByUser(channel, nickname, text))
			case let (.some(channel), nil):
				String(localized: .Notifications.spokenHighlightInChannel(channel, text))
			case let (nil, .some(nickname)):
				String(localized: .Notifications.spokenHighlightByUser(nickname, text))
			case (nil, nil):
				text
			}
		}

		private static func channelMessage(channelName: String?, nickname: String?, text: String) -> String {
			switch (channelName, nickname) {
			case let (.some(channel), .some(nickname)):
				String(localized: .Notifications.spokenChannelMessageInChannelByUser(channel, nickname, text))
			case let (.some(channel), nil):
				String(localized: .Notifications.spokenChannelMessageInChannel(channel, text))
			case let (nil, .some(nickname)):
				String(localized: .Notifications.spokenChannelMessageByUser(nickname, text))
			case (nil, nil):
				text
			}
		}

		private static func channelNotice(channelName: String?, nickname: String?, text: String) -> String {
			switch (channelName, nickname) {
			case let (.some(channel), .some(nickname)):
				String(localized: .Notifications.spokenChannelNoticeInChannelByUser(channel, nickname, text))
			case let (.some(channel), nil):
				String(localized: .Notifications.spokenChannelNoticeInChannel(channel, text))
			case let (nil, .some(nickname)):
				String(localized: .Notifications.spokenChannelNoticeByUser(nickname, text))
			case (nil, nil):
				text
			}
		}

		static func connected(to networkName: String) -> String {
			String(localized: .Notifications.spokenConnected(networkName))
		}

		static func disconnected(from networkName: String) -> String {
			String(localized: .Notifications.spokenDisconnected(networkName))
		}

		static func privateMessage(
			for event: NotificationEvent,
			from nickname: String,
			text: String
		) -> String? {
			switch event {
			case .newPrivateMessage:
				String(localized: .Notifications.spokenNewPrivateMessage(nickname, text))
			case .privateMessage:
				String(localized: .Notifications.spokenPrivateMessage(nickname, text))
			case .privateNotice:
				String(localized: .Notifications.spokenPrivateNotice(nickname, text))
			default:
				nil
			}
		}

		static func kicked(from channelName: String, by nickname: String) -> String {
			String(localized: .Notifications.spokenKicked(channelName, nickname))
		}

		static func invited(to channelName: String, by nickname: String) -> String {
			String(localized: .Notifications.spokenInvited(channelName, nickname))
		}

		static func fileTransfer(for event: NotificationEvent, with nickname: String) -> String? {
			switch event {
			case .fileTransferSendSuccessful:
				String(localized: .Notifications.spokenFileTransferSendCompleted(nickname))
			case .fileTransferReceiveSuccessful:
				String(localized: .Notifications.spokenFileTransferReceiveCompleted(nickname))
			case .fileTransferSendFailed:
				String(localized: .Notifications.spokenFileTransferSendFailed(nickname))
			case .fileTransferReceiveFailed:
				String(localized: .Notifications.spokenFileTransferReceiveFailed(nickname))
			case .fileTransferReceiveRequested:
				String(localized: .Notifications.spokenFileTransferRequest(nickname))
			default:
				nil
			}
		}

		static func membership(
			for event: NotificationEvent,
			nickname: String,
			channelName: String
		) -> String? {
			switch event {
			case .userJoined:
				String(localized: .Notifications.spokenUserJoined(nickname, channelName))
			case .userParted:
				String(localized: .Notifications.spokenUserParted(nickname, channelName))
			default:
				nil
			}
		}

		static func userDisconnected(_ nickname: String) -> String {
			String(localized: .Notifications.spokenUserDisconnected(nickname))
		}
	}

	/** The sentence under a membership notification's heading.

	 The channel and the network are already the notification's title and
	 subtitle, so these name only the person and, where there is one, their
	 reason. */
	enum Membership {
		static func kicked(by nickname: String, reason: String?) -> String {
			if let reason, reason.isEmpty == false {
				return String(localized: .Notifications.bodyKicked(nickname, reason))
			}

			return String(localized: .Notifications.bodyKickedWithoutReason(nickname))
		}

		static func invited(by nickname: String, to channelName: String) -> String {
			String(localized: .Notifications.bodyInvited(nickname, channelName))
		}

		static func joined(nickname: String) -> String {
			String(localized: .Notifications.bodyUserJoined(nickname))
		}

		static func parted(nickname: String, reason: String?) -> String {
			if let reason, reason.isEmpty == false {
				return String(localized: .Notifications.bodyUserPartedWithReason(nickname, reason))
			}

			return String(localized: .Notifications.bodyUserParted(nickname))
		}

		static func disconnected(nickname: String, reason: String?) -> String {
			if let reason, reason.isEmpty == false {
				return String(localized: .Notifications.bodyUserDisconnectedWithReason(nickname, reason))
			}

			return String(localized: .Notifications.bodyUserDisconnected(nickname))
		}
	}

	enum Availability {
		static func message(
			for status: IRCAddressBookUserTrackingStatus,
			nickname: String
		) -> String? {
			switch status {
			case .signedOn:
				String(localized: .Notifications.bodyUserNowAvailable(nickname))
			case .signedOff:
				String(localized: .Notifications.bodyUserNoLongerAvailable(nickname))
			case .available:
				String(localized: .Notifications.bodyUserAvailable(nickname))
			default:
				nil
			}
		}
	}

	enum FileTransfer {
		static func description(
			for event: NotificationEvent,
			filename: String,
			byteCount: UInt64
		) -> String? {
			switch event {
			case .fileTransferSendSuccessful:
				String(
					localized: .Notifications.bodyFileTransferSendSuccessful(
						filename,
						LocalizedByteCount.formatted(byteCount)
					)
				)
			case .fileTransferReceiveSuccessful:
				String(
					localized: .Notifications.bodyFileTransferReceiveSuccessful(
						filename,
						LocalizedByteCount.formatted(byteCount)
					)
				)
			case .fileTransferSendFailed:
				String(localized: .Notifications.bodyFileTransferSendFailed(filename))
			case .fileTransferReceiveFailed:
				String(localized: .Notifications.bodyFileTransferReceiveFailed(filename))
			case .fileTransferReceiveRequested:
				String(
					localized: .Notifications.bodyFileTransferRequest(
						filename,
						LocalizedByteCount.formatted(byteCount)
					)
				)
			default:
				nil
			}
		}
	}
}

nonisolated enum NotificationSoundStrings { // nonisolated: value
	static var defaultSound: String {
		String(localized: .NotificationSettings.defaultSound)
	}

	static var noSound: String {
		String(localized: .NotificationSettings.noSound)
	}
}

nonisolated enum NotificationConfigurationStrings { // nonisolated: value
	static var event: String {
		String(localized: .NotificationSettings.event)
	}

	static var showNotification: String {
		String(localized: .NotificationSettings.showNotification)
	}

	static var speak: String {
		String(localized: .NotificationSettings.speak)
	}

	static var disableWhileAway: String {
		String(localized: .NotificationSettings.disableWhileAway)
	}

	static var bounceDockIcon: String {
		String(localized: .NotificationSettings.bounceDockIcon)
	}

	static var bounceRepeatedly: String {
		String(localized: .NotificationSettings.bounceRepeatedly)
	}

	static var sound: String {
		String(localized: .NotificationSettings.sound)
	}

	static var inherit: String {
		String(localized: .NotificationSettings.inherit)
	}

	static var off: String {
		String(localized: .NotificationSettings.off)
	}

	static var on: String {
		String(localized: .NotificationSettings.on)
	}

	static var noEvents: String {
		String(localized: .NotificationSettings.noNotificationEvents)
	}
}
