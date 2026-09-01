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

	static func eventTypeTitle(for event: TXNotificationType) -> String {
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

	static func deliveredTitle(for event: TXNotificationType, subject: String?) -> String? {
		switch event {
		case .highlight:
			String(localized: .Notifications.titleHighlight(subject ?? ""))
		case .newPrivateMessage:
			String(localized: .Notifications.titleNewPrivateMessage)
		case .channelMessage:
			String(localized: .Notifications.titleChannelMessage(subject ?? ""))
		case .channelNotice:
			String(localized: .Notifications.titleChannelNotice(subject ?? ""))
		case .privateMessage:
			String(localized: .Notifications.titlePrivateMessage)
		case .privateNotice:
			String(localized: .Notifications.titlePrivateNotice)
		case .kick:
			String(localized: .Notifications.titleKicked(subject ?? ""))
		case .invite:
			String(localized: .Notifications.titleInvited(subject ?? ""))
		case .connect:
			String(localized: .Notifications.titleConnected(subject ?? ""))
		case .disconnect:
			String(localized: .Notifications.titleDisconnected(subject ?? ""))
		case .addressBookMatch:
			String(localized: .Notifications.titleAddressBook)
		case .fileTransferSendSuccessful:
			String(localized: .Notifications.titleFileTransferSendSuccessful(subject ?? ""))
		case .fileTransferReceiveSuccessful:
			String(localized: .Notifications.titleFileTransferReceiveSuccessful(subject ?? ""))
		case .fileTransferSendFailed:
			String(localized: .Notifications.titleFileTransferSendFailed(subject ?? ""))
		case .fileTransferReceiveFailed:
			String(localized: .Notifications.titleFileTransferReceiveFailed(subject ?? ""))
		case .fileTransferReceiveRequested:
			String(localized: .Notifications.titleFileTransferRequest(subject ?? ""))
		case .userJoined:
			String(localized: .Notifications.titleUserJoined(subject ?? ""))
		case .userParted:
			String(localized: .Notifications.titleUserParted(subject ?? ""))
		case .userDisconnected:
			String(localized: .Notifications.titleUserDisconnected(subject ?? ""))
		}
	}

	static func deliveredBody(for event: TXNotificationType, fallback: String?) -> String? {
		switch event {
		case .connect:
			String(localized: .Notifications.bodyConnectionSuccessful)
		case .disconnect:
			String(localized: .Notifications.bodyDisconnectionSuccessful)
		default:
			fallback
		}
	}

	enum Spoken {
		static var channelMessage: String {
			String(localized: .Notifications.spokenChannelMessage)
		}

		static var channelNotice: String {
			String(localized: .Notifications.spokenChannelNotice)
		}

		static var highlight: String {
			String(localized: .Notifications.spokenHighlight)
		}

		static var privateMessageLocation: String {
			String(localized: .Notifications.spokenInPrivateMessage)
		}

		static var separator: String {
			String(localized: .Notifications.spokenSeparator)
		}

		static func author(_ nickname: String) -> String {
			String(localized: .Notifications.spokenByUser(nickname))
		}

		static func channel(_ channelName: String) -> String {
			String(localized: .Notifications.spokenInChannel(channelName))
		}

		static func connected(to networkName: String) -> String {
			String(localized: .Notifications.spokenConnected(networkName))
		}

		static func disconnected(from networkName: String) -> String {
			String(localized: .Notifications.spokenDisconnected(networkName))
		}

		static func privateMessageAuthor(_ nickname: String) -> String {
			String(localized: .Notifications.spokenFromUser(nickname))
		}

		static func privateMessage(
			for event: TXNotificationType,
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

		static func fileTransfer(for event: TXNotificationType, with nickname: String) -> String? {
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
			for event: TXNotificationType,
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

	enum Membership {
		static func kicked(by nickname: String, from channelName: String, reason: String) -> String {
			String(localized: .Notifications.bodyKicked(nickname, channelName, reason))
		}

		static func invited(by nickname: String, to channelName: String) -> String {
			String(localized: .Notifications.bodyInvited(nickname, channelName))
		}

		static func joined(nickname: String, channelName: String) -> String {
			String(localized: .Notifications.bodyUserJoined(nickname, channelName))
		}

		static func parted(nickname: String, channelName: String, reason: String?) -> String {
			if let reason, reason.isEmpty == false {
				return String(localized: .Notifications.bodyUserPartedWithReason(nickname, channelName, reason))
			}

			return String(localized: .Notifications.bodyUserParted(nickname, channelName))
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
			for event: TXNotificationType,
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
		String(localized: .TVCNotificationConfigurationView.defaultSound)
	}

	static var noSound: String {
		String(localized: .TVCNotificationConfigurationView.noSound)
	}
}

nonisolated enum NotificationConfigurationStrings { // nonisolated: value
	static var bounceDockIcon: String {
		String(localized: .TVCNotificationConfigurationView.bounceDockIcon)
	}

	static var bounceRepeatedly: String {
		String(localized: .TVCNotificationConfigurationView.bounceRepeatedly)
	}

	static var disableWhileAway: String {
		String(localized: .TVCNotificationConfigurationView.disableWhileAway)
	}

	static var inherit: String {
		String(localized: .TVCNotificationConfigurationView.inherit)
	}

	static var noAlerts: String {
		String(localized: .TVCNotificationConfigurationView.noAlerts)
	}

	static var off: String {
		String(localized: .TVCNotificationConfigurationView.off)
	}

	static var on: String {
		String(localized: .TVCNotificationConfigurationView.on)
	}

	static var selectedAlert: String {
		String(localized: .TVCNotificationConfigurationView.selectedAlert)
	}

	static var showNotification: String {
		String(localized: .TVCNotificationConfigurationView.showNotification)
	}

	static var sound: String {
		String(localized: .TVCNotificationConfigurationView.sound)
	}

	static var speak: String {
		String(localized: .TVCNotificationConfigurationView.speak)
	}
}
