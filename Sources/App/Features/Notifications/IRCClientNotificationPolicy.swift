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

/// Where one event's alert sound comes from.
enum IRCNotificationSoundPlayback: Equatable {
	/// The notification carries it, so the system plays it.
	case withNotification
	/// The application plays it, because the system will not.
	case byApplication
	/// Nothing plays it: the sounds are muted, the event has none, or the event
	/// is only being spoken and nothing is posted to carry one.
	case silent
}

enum IRCNotificationAdmission: Equatable {
	case discard
	case handled
	case proceed
}

struct IRCNotificationAdmissionContext {
	let event: NotificationEvent
	let isTerminating: Bool
	let isCollapsingNetsplit: Bool
	let nicknameIsLocalUser: Bool
	let outputIsSuppressed: Bool
	let targetIgnoresHighlights: Bool
	let targetDisablesPush: Bool
}

enum IRCNotificationPolicy {
	static func isTextEvent(_ event: NotificationEvent) -> Bool {
		switch event {
		case .highlight, .newPrivateMessage, .channelMessage, .channelNotice, .privateMessage, .privateNotice:
			true
		default:
			false
		}
	}

	static func admission(for context: IRCNotificationAdmissionContext) -> IRCNotificationAdmission {
		if context.isTerminating {
			return .discard
		}

		if context.isCollapsingNetsplit,
		   context.event == .userJoined || context.event == .userDisconnected
		{
			return .discard
		}

		if isTextEvent(context.event), context.nicknameIsLocalUser {
			return .discard
		}

		if context.outputIsSuppressed {
			return .discard
		}

		if context.event == .highlight {
			return context.targetIgnoresHighlights ? .handled : .proceed
		}

		return context.targetDisablesPush ? .handled : .proceed
	}

	static func shouldOnlySpeak(
		postWhileFocused: Bool,
		mainWindowIsFocused: Bool,
		targetIsSelected: Bool
	) -> Bool {
		postWhileFocused && mainWindowIsFocused && targetIsSelected
	}

	static func shouldPostUserNotification(
		event: NotificationEvent,
		notificationEnabled: Bool,
		postWhileFocused: Bool,
		mainWindowIsFocused: Bool,
		disabledWhileAway: Bool,
		userIsAway: Bool
	) -> Bool {
		guard notificationEnabled else { return false }

		if postWhileFocused == false, mainWindowIsFocused, event != .addressBookMatch {
			return false
		}

		if disabledWhileAway, userIsAway {
			return false
		}

		return true
	}

	/** Who plays the alert sound for one event.

	 A notification is where a sound belongs: the system applies Do Not Disturb,
	 the alert volume and the notification's own settings to it, none of which an
	 `AudioServicesPlayAlertSound` played behind its back honours. The
	 application plays one itself only where the system will not — permission
	 refused, or sounds switched off for the application.

	 `systemPlaysNotificationSounds` is `nil` until the first settings read
	 answers, which is a moment after launch. Reading that as "the system will
	 not" is what would play the first sounds of a session twice: once here and
	 once from the notification the system had every right to sound. */
	static func soundPlayback(
		soundName: String?,
		isMuted: Bool,
		isOnlySpoken: Bool,
		systemPlaysNotificationSounds: Bool?
	) -> IRCNotificationSoundPlayback {
		guard isMuted == false, soundName != nil, isOnlySpoken == false else {
			return .silent
		}

		return systemPlaysNotificationSounds == false ? .byApplication : .withNotification
	}

	static func notificationUserInfo(
		clientIdentifier: String,
		channelIdentifier: String?
	) -> NotificationPayload {
		NotificationPayload(clientIdentifier: clientIdentifier, channelIdentifier: channelIdentifier)
	}

	static func textEventDescription(
		lineType: LogLineType,
		nickname: String,
		formattedNickname: String,
		text: String
	) -> String {
		if lineType == .action || lineType == .actionNoHighlight {
			return NotificationStrings.actionBody(nickname: nickname, text: text)
		}

		return NotificationStrings.messageBody(formattedNickname: formattedNickname, text: text)
	}
}

struct IRCSpokenMessageVisibility: Equatable {
	let shouldSpeak: Bool
	let includesChannelName: Bool
	let includesNickname: Bool
}

enum IRCSpokenNotificationPolicy {
	static func highlightVisibility(
		isChannel: Bool,
		onlySpeakSelection: Bool,
		channelIsSelected: Bool,
		includeConfiguredChannelName: Bool,
		includeConfiguredNickname: Bool
	) -> IRCSpokenMessageVisibility {
		let includesChannelName = !isChannel ||
			(!onlySpeakSelection && includeConfiguredChannelName) ||
			(onlySpeakSelection && !channelIsSelected)
		let includesNickname = !isChannel || includeConfiguredNickname

		return IRCSpokenMessageVisibility(
			shouldSpeak: true,
			includesChannelName: includesChannelName,
			includesNickname: includesNickname
		)
	}

	static func channelMessageVisibility(
		onlySpeakSelection: Bool,
		channelIsSelected: Bool,
		includeConfiguredChannelName: Bool,
		includeConfiguredNickname: Bool
	) -> IRCSpokenMessageVisibility {
		let shouldSpeak = !onlySpeakSelection || channelIsSelected
		return IRCSpokenMessageVisibility(
			shouldSpeak: shouldSpeak,
			includesChannelName: shouldSpeak && !onlySpeakSelection && includeConfiguredChannelName,
			includesNickname: shouldSpeak && includeConfiguredNickname
		)
	}
}
