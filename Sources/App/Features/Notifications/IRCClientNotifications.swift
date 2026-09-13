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

import AppKit
import CocoaExtensions
import Foundation

public extension IRCClient {
	private func formatSpokenNotification(
		_ event: NotificationEvent,
		channel: Channel?,
		nickname: String?,
		text rawText: String?
	) -> String? {
		guard !isTerminating else { return nil }

		let text = normalizedSpeechText(rawText)

		switch event {
		case .highlight:
			return formatSpokenHighlight(channel: channel, nickname: nickname, text: text)

		case .channelMessage, .channelNotice:
			return formatSpokenChannelEvent(event, channel: channel, nickname: nickname, text: text)

		case .newPrivateMessage, .privateMessage, .privateNotice:
			return formatSpokenPrivateEvent(event, nickname: nickname, text: text)

		case .kick:
			return formatSpokenKick(channel: channel, nickname: nickname)

		case .invite:
			return formatSpokenInvite(nickname: nickname, channelName: text)

		case .connect:
			return NotificationStrings.Spoken.connected(to: networkNameAlt)

		case .disconnect:
			return NotificationStrings.Spoken.disconnected(from: networkNameAlt)

		case .addressBookMatch:
			return text

		case .fileTransferSendSuccessful, .fileTransferReceiveSuccessful, .fileTransferSendFailed,
		     .fileTransferReceiveFailed, .fileTransferReceiveRequested:
			return formatSpokenFileTransfer(event, nickname: nickname)

		case .userJoined, .userParted:
			return formatSpokenMembership(event, channel: channel, nickname: nickname)

		case .userDisconnected:
			return nickname.map(NotificationStrings.Spoken.userDisconnected)
		}
	}

	@MainActor
	private func formatSpokenHighlight(channel: Channel?, nickname: String?, text: String?) -> String? {
		guard let channel, let nickname, let text, !text.isEmpty else { return nil }
		let visibility = IRCSpokenNotificationPolicy.highlightVisibility(
			isChannel: channel.isChannel,
			onlySpeakSelection: Preferences.Notifications.onlySpeakForSelection.value,
			channelIsSelected: isSelected(channel),
			includeConfiguredChannelName: Preferences.Notifications.flag(.channelMessage, .speakChannelName).value,
			includeConfiguredNickname: Preferences.Notifications.flag(.channelMessage, .speakNickname).value
		)

		guard channel.isChannel else {
			return NotificationStrings.Spoken.privateHighlight(from: nickname, text: text)
		}

		return NotificationStrings.Spoken.channelEvent(
			.highlight,
			channelName: visibility.includesChannelName ? spokenChannelName(channel) : nil,
			nickname: visibility.includesNickname ? nickname : nil,
			text: text
		)
	}

	@MainActor
	private func formatSpokenChannelEvent(
		_ event: NotificationEvent,
		channel: Channel?,
		nickname: String?,
		text: String?
	) -> String? {
		guard let channel, let nickname, let text, !text.isEmpty else { return nil }
		let visibility = IRCSpokenNotificationPolicy.channelMessageVisibility(
			onlySpeakSelection: Preferences.Notifications.onlySpeakForSelection.value,
			channelIsSelected: isSelected(channel),
			includeConfiguredChannelName: Preferences.Notifications.flag(.channelMessage, .speakChannelName).value,
			includeConfiguredNickname: Preferences.Notifications.flag(.channelMessage, .speakNickname).value
		)
		guard visibility.shouldSpeak else { return nil }

		return NotificationStrings.Spoken.channelEvent(
			event,
			channelName: visibility.includesChannelName ? spokenChannelName(channel) : nil,
			nickname: visibility.includesNickname ? nickname : nil,
			text: text
		)
	}

	private func formatSpokenPrivateEvent(
		_ event: NotificationEvent,
		nickname: String?,
		text: String?
	) -> String? {
		guard let nickname, let text, !text.isEmpty else { return nil }
		return NotificationStrings.Spoken.privateMessage(for: event, from: nickname, text: text)
	}

	@MainActor
	private func formatSpokenKick(channel: Channel?, nickname: String?) -> String? {
		guard let channel, let nickname else { return nil }
		return NotificationStrings.Spoken.kicked(from: spokenChannelName(channel), by: nickname)
	}

	private func formatSpokenInvite(nickname: String?, channelName: String?) -> String? {
		guard let nickname, let channelName else { return nil }
		let nameWithoutBang = (channelName as NSString).channelNameWithoutPrefix
		return NotificationStrings.Spoken.invited(to: nameWithoutBang, by: nickname)
	}

	private func formatSpokenFileTransfer(_ event: NotificationEvent, nickname: String?) -> String? {
		guard let nickname else { return nil }
		return NotificationStrings.Spoken.fileTransfer(for: event, with: nickname)
	}

	@MainActor
	private func formatSpokenMembership(
		_ event: NotificationEvent,
		channel: Channel?,
		nickname: String?
	) -> String? {
		guard let channel, let nickname else { return nil }
		return NotificationStrings.Spoken.membership(
			for: event,
			nickname: nickname,
			channelName: spokenChannelName(channel)
		)
	}

	@MainActor
	private func normalizedSpeechText(_ text: String?) -> String? {
		guard var text else { return nil }
		text = text.trimmingCharacters(in: .whitespacesAndNewlines)
		if !Preferences.Messages.removeAllFormatting.value {
			text = (text as NSString).stripIRCEffects
		}
		return text
	}

	@MainActor
	private func spokenChannelName(_ channel: Channel) -> String {
		(channel.name as NSString).channelNameWithoutPrefix
	}

	@MainActor
	private func isSelected(_ channel: Channel?) -> Bool {
		guard let channel else { return false }
		return AppController.shared.mainWindow?.isItemSelected(channel) ?? false
	}

	func clearEventsToSpeak() {
		SharedApplication.sharedSpeechSynthesizer().clearQueue(for: self)
	}

	func speakEvent(
		_ event: NotificationEvent,
		lineType: LogLineType,
		target: TreeItem?,
		nickname: String?,
		text: String?
	) {
		let resolvedTarget = target ?? self
		let channel = resolvedTarget as? Channel
		guard SharedApplication.sharedNotificationController().speakEvent(event, in: channel) else { return }
		var notification = SpokenNotification(
			notificationType: event,
			lineType: lineType,
			target: resolvedTarget,
			nickname: nickname,
			text: text
		)
		/* Formatting reads the client and the channel, so it happens here rather
		 than on the synthesizer's queue. */
		notification.spokenText = formatSpokenNotification(
			event,
			channel: channel,
			nickname: nickname,
			text: text
		)
		SharedApplication.sharedSpeechSynthesizer().speak(.notification(notification))
	}

	/** Raises one event: the Dock bounce, the sound, the spoken line and the
	 notification itself.

	 Returns whether the event was answered — `false` only where the event is
	 discarded outright, which is what tells the caller nothing was shown. */
	@MainActor
	func notifyEvent(
		_ event: NotificationEvent,
		lineType: LogLineType,
		target: Channel? = nil,
		nickname: String? = nil,
		text: String? = nil,
		userInfo suppliedUserInfo: NotificationPayload? = nil
	) -> Bool {
		let admission = IRCNotificationPolicy.admission(for: IRCNotificationAdmissionContext(
			event: event,
			isTerminating: isTerminating,
			isCollapsingNetsplit: collapsedNetsplitBatch != nil,
			nicknameIsLocalUser: nickname.map(nicknameIsMyself) ?? false,
			targetIgnoresHighlights: target?.config.ignoreHighlights ?? false,
			targetDisablesPush: target.map { !$0.config.pushNotifications } ?? false
		))
		switch admission {
		case .discard: return false
		case .handled: return true
		case .proceed: break
		}

		let controller = SharedApplication.sharedNotificationController()
		if controller.bounceDockIcon(forEvent: event, in: target) {
			let requestType: NSApplication.RequestUserAttentionType =
				controller.bounceDockIconRepeatedly(forEvent: event, in: target)
					? .criticalRequest
					: .informationalRequest
			NSApp.requestUserAttention(requestType)
		}

		guard !controller.areNotificationsDisabled else { return true }

		let mainWindowIsFocused = AppController.shared.mainWindow?.ceIsInactive == false
		let postWhileFocused = Preferences.Notifications.postWhileInFocus.value
		let targetIsSelected = isSelected(target)
		let onlySpeak = IRCNotificationPolicy.shouldOnlySpeak(
			postWhileFocused: postWhileFocused,
			mainWindowIsFocused: mainWindowIsFocused,
			targetIsSelected: targetIsSelected
		)

		let soundIsMuted = Preferences.Notifications.soundIsMuted.value
		let soundName = soundIsMuted ? nil : controller.sound(forEvent: event, in: target)
		let soundPlayback = IRCNotificationPolicy.soundPlayback(
			soundName: soundName,
			isMuted: soundIsMuted,
			isOnlySpoken: onlySpeak,
			systemSoundDelivery: controller.systemSoundDelivery
		)
		/* Exactly one of the two plays it: the notification carries the sound
		 unless the system will not play it, in which case the application does
		 and the notification is posted silent. */
		let notificationSound = soundPlayback == .withNotification ? soundName : nil

		if !soundIsMuted {
			if soundPlayback == .byApplication, let soundName {
				SoundPlayer.playAlertSound(soundName)
			}
			speakEvent(event, lineType: lineType, target: target, nickname: nickname, text: text)
		}

		guard !onlySpeak else { return true }
		guard IRCNotificationPolicy.shouldPostUserNotification(
			event: event,
			notificationEnabled: controller.notificationEnabled(forEvent: event, in: target),
			postWhileFocused: postWhileFocused,
			mainWindowIsFocused: mainWindowIsFocused,
			disabledWhileAway: controller.disabledWhileAway(forEvent: event, in: target),
			userIsAway: userIsAway
		) else { return true }

		let userInfo = suppliedUserInfo ?? IRCNotificationPolicy.notificationUserInfo(
			clientIdentifier: uniqueIdentifier,
			channelIdentifier: target?.uniqueIdentifier
		)
		guard let content = notificationContent(
			for: event,
			lineType: lineType,
			target: target,
			nickname: nickname,
			text: text
		) else { return true }

		controller.post(
			title: content.title,
			subtitle: content.subtitle,
			body: content.body,
			sound: notificationSound,
			userInfo: userInfo,
			categoryIdentifier: NotificationController.categoryIdentifier(for: event)
		)

		return true
	}

	/** What one event's notification says.

	 The title is who or what it is about, the subtitle is where it happened and
	 the body is the detail — the shape Messages and Mail use, and the shape
	 every event takes. An event nobody spoke is titled with its own name, the
	 same phrase the notification settings table lists it under. */
	@MainActor
	private func notificationContent(
		for event: NotificationEvent,
		lineType: LogLineType,
		target: Channel?,
		nickname: String?,
		text: String?
	) -> NotificationContent? {
		switch event {
		case .highlight, .newPrivateMessage, .channelMessage, .channelNotice, .privateMessage, .privateNotice:
			textNotificationContent(
				for: event,
				lineType: lineType,
				target: target,
				nickname: nickname,
				text: text
			)

		case .fileTransferSendSuccessful, .fileTransferReceiveSuccessful, .fileTransferSendFailed,
		     .fileTransferReceiveFailed, .fileTransferReceiveRequested:
			nickname.map {
				NotificationContent(
					title: NotificationStrings.eventTypeTitle(for: event),
					subtitle: $0,
					body: text
				)
			}

		case .connect, .disconnect:
			NotificationContent(
				title: NotificationStrings.eventTypeTitle(for: event),
				subtitle: networkNameAlt
			)

		case .addressBookMatch:
			text.map {
				NotificationContent(
					title: NotificationStrings.eventTypeTitle(for: event),
					subtitle: networkNameAlt,
					body: $0
				)
			}

		case .kick, .invite, .userJoined, .userParted, .userDisconnected:
			membershipNotificationContent(
				for: event,
				target: target,
				nickname: nickname,
				text: text
			)
		}
	}

	/** Who said it, where, and what they said — as three fields.

	 A message notification reads like every other one on the system: the
	 nickname in the title, the channel in the subtitle, the message in the
	 body. An action keeps its composed "nickname does something" body, because
	 there the nickname is part of the sentence. */
	@MainActor
	private func textNotificationContent(
		for event: NotificationEvent,
		lineType: LogLineType,
		target: Channel?,
		nickname: String?,
		text: String?
	) -> NotificationContent? {
		guard let nickname, let text else { return nil }
		let location: String? = switch event {
		case .highlight, .channelMessage, .channelNotice: target?.name
		default: nil
		}
		let formattedNickname = formatNickname(nickname, in: target)
		let isAction = lineType == .action || lineType == .actionNoHighlight
		let body = isAction
			? NotificationStrings.actionBody(nickname: nickname, text: text)
			: text

		return NotificationContent(title: formattedNickname, subtitle: location, body: body)
	}

	/** Where it happened in the title and subtitle, who did it in the body.

	 The channel and the network are the notification's own heading, so the
	 sentence underneath names only the person and their reason. */
	private func membershipNotificationContent(
		for event: NotificationEvent,
		target: Channel?,
		nickname: String?,
		text: String?
	) -> NotificationContent? {
		guard let nickname else { return nil }
		let title = NotificationStrings.eventTypeTitle(for: event)

		switch event {
		case .kick:
			guard let target else { return nil }
			return NotificationContent(
				title: title,
				subtitle: target.name,
				body: NotificationStrings.Membership.kicked(by: nickname, reason: text)
			)
		case .invite:
			guard let text else { return nil }
			return NotificationContent(
				title: title,
				subtitle: networkNameAlt,
				body: NotificationStrings.Membership.invited(by: nickname, to: text)
			)
		case .userJoined:
			guard let target else { return nil }
			return NotificationContent(
				title: title,
				subtitle: target.name,
				body: NotificationStrings.Membership.joined(nickname: nickname)
			)
		case .userParted:
			guard let target else { return nil }
			return NotificationContent(
				title: title,
				subtitle: target.name,
				body: NotificationStrings.Membership.parted(nickname: nickname, reason: text)
			)
		case .userDisconnected:
			return NotificationContent(
				title: title,
				subtitle: networkNameAlt,
				body: NotificationStrings.Membership.disconnected(nickname: nickname, reason: text)
			)
		default:
			return nil
		}
	}
}

/** What one notification says.

 The title is who or what it is about, the subtitle is where it happened and
 the body is the detail. Every event fills the title; the rest is what it has. */
struct NotificationContent {
	var title: String
	var subtitle: String?
	var body: String?
}
