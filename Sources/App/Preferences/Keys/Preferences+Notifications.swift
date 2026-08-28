/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
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

/// The per-event settings each notification type carries.
public nonisolated enum NotificationSetting: String, CaseIterable, Sendable {
	case enabled = "Enabled"
	case sound = "Sound"
	case disabledWhileAway = "Disable While Away"
	case bounceDockIcon = "Bounce Dock Icon"
	case bounceDockIconRepeatedly = "Bounce Dock Icon Repeatedly"
	case speak = "Speak"
	case speakChannelName = "Speak Channel Name"
	case speakNickname = "Speak Nickname"
}

public nonisolated extension TXNotificationType {
	/// The preference-key prefix this event's settings live under.
	var preferenceKeyPrefix: String {
		let name = switch self {
		case .addressBookMatch: "Address Book Match"
		case .channelMessage: "Public Message"
		case .channelNotice: "Public Notice"
		case .connect: "Connected"
		case .disconnect: "Disconnected"
		case .highlight: "Highlight"
		case .invite: "Channel Invitation"
		case .kick: "Kicked from Channel"
		case .newPrivateMessage: "Private Message (New)"
		case .privateMessage: "Private Message"
		case .privateNotice: "Private Notice"
		case .fileTransferSendSuccessful: "Successful File Transfer (Sending)"
		case .fileTransferReceiveSuccessful: "Successful File Transfer (Receiving)"
		case .fileTransferSendFailed: "Failed File Transfer (Sending)"
		case .fileTransferReceiveFailed: "Failed File Transfer (Receiving)"
		case .fileTransferReceiveRequested: "File Transfer Request"
		case .userJoined: "User Joined"
		case .userParted: "User Parted"
		case .userDisconnected: "User Disconnected"
		}

		return "\(Preferences.Notifications.keyPrefix)\(name) -> "
	}

	func preferenceKeyName(for setting: NotificationSetting) -> String {
		preferenceKeyPrefix + setting.rawValue
	}
}

public nonisolated extension Preferences {
	/// Per-event notification settings, plus the switches that apply to all of
	/// them.
	nonisolated enum Notifications {
		static let keyPrefix = "NotificationType -> "

		/// The individual `NotificationType -> …` keys are matched by prefix in
		/// the catalogue rather than listed one by one, because a name is made
		/// from an event and a setting at the point of use.
		public static let family = PreferenceKeyFamily(keyPrefix)

		public static let soundIsMuted = PreferenceKey(
			"Notification Sound Is Muted",
			default: false,
			traits: .unregistered
		)

		public static let onlySpeakForSelection = PreferenceKey(
			"OnlySpeakNotificationsForSelection",
			default: true
		)

		public static let postWhileInFocus = PreferenceKey("PostNotificationsWhileInFocus", default: true)
		public static let displayDockBadge = PreferenceKey("DisplayDockBadges", default: true)

		public static let publicMessageCountOnDockBadge = PreferenceKey(
			"DisplayPublicMessageCountInDockBadge",
			default: false
		)

		/// A typed key for one event's setting. Reads fall back to whatever the
		/// registration domain holds for it, so the `false`/`""` here only
		/// applies to a setting that ships with no default at all.
		static func flag(
			_ event: TXNotificationType,
			_ setting: NotificationSetting
		) -> PreferenceKey<Bool> {
			PreferenceKey(event.preferenceKeyName(for: setting), default: false, traits: .uncatalogued)
		}

		static func sound(_ event: TXNotificationType) -> PreferenceKey<String> {
			PreferenceKey(event.preferenceKeyName(for: .sound), default: "", traits: .uncatalogued)
		}

		/** The settings that ship switched on, by event; anything not listed
		 defaults to off. `.enabled` and `.bounceDockIcon` travel together for
		 every event that has either, which is why one list covers both. */
		private static let enabledByDefault: [(event: TXNotificationType, settings: [NotificationSetting])] = [
			(.addressBookMatch, [.enabled]),
			(.channelMessage, [.speakChannelName, .speakNickname]),
			(.highlight, [.enabled, .bounceDockIcon]),
			(.newPrivateMessage, [.enabled, .bounceDockIcon]),
			(.privateMessage, [.enabled, .bounceDockIcon]),
			(.fileTransferReceiveRequested, [.enabled, .bounceDockIcon]),
			(.fileTransferSendSuccessful, [.enabled, .bounceDockIcon]),
			(.fileTransferReceiveSuccessful, [.enabled, .bounceDockIcon]),
			(.fileTransferSendFailed, [.enabled, .bounceDockIcon]),
			(.fileTransferReceiveFailed, [.enabled, .bounceDockIcon]),
		]

		private static let registeredSounds: [(TXNotificationType, String)] = [
			(.highlight, "Glass"),
			(.newPrivateMessage, "Submarine"),
			(.privateMessage, "Submarine"),
			(.fileTransferReceiveRequested, "Blow"),
		]

		static let all: [any AnyPreferenceKey] = {
			var keys: [any AnyPreferenceKey] = [
				soundIsMuted, onlySpeakForSelection, postWhileInFocus, displayDockBadge,
				publicMessageCountOnDockBadge,
			]

			for (event, settings) in enabledByDefault {
				for setting in settings {
					keys.append(
						PreferenceKey(
							event.preferenceKeyName(for: setting),
							default: true,
							traits: .uncatalogued
						)
					)
				}
			}

			for (event, soundName) in registeredSounds {
				keys.append(
					PreferenceKey(
						event.preferenceKeyName(for: .sound),
						default: soundName,
						traits: .uncatalogued
					)
				)
			}

			return keys
		}()
	}
}
