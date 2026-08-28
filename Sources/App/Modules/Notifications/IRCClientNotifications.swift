/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\\__|\__,_|\__,_|_|
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
	private func formatSpokenNotification(_ notification: SpokenNotification) -> String? {
		guard !isTerminating else { return nil }

		let event = notification.notificationType
		let channel = notification.channel
		let nickname = notification.nickname
		let text = normalizedSpeechText(notification.text)

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

		@unknown default:
			return nil
		}
	}

	@MainActor
	private func formatSpokenHighlight(channel: IRCChannel?, nickname: String?, text: String?) -> String? {
		guard let channel, let nickname, let text, !text.isEmpty else { return nil }
		let visibility = IRCSpokenNotificationPolicy.highlightVisibility(
			isChannel: channel.isChannel,
			onlySpeakSelection: TextualPreferences.onlySpeakEventsForSelection(),
			channelIsSelected: isSelected(channel),
			includeConfiguredChannelName: TextualPreferences.channelMessageSpeakChannelName(),
			includeConfiguredNickname: TextualPreferences.channelMessageSpeakNickname()
		)
		var message = NotificationStrings.Spoken.highlight
		if visibility.includesChannelName || visibility.includesNickname {
			if visibility.includesChannelName {
				message += channel.isChannel
					? NotificationStrings.Spoken.channel(spokenChannelName(channel))
					: NotificationStrings.Spoken.privateMessageLocation
			}
			if visibility.includesNickname {
				message += channel.isChannel
					? NotificationStrings.Spoken.author(nickname)
					: NotificationStrings.Spoken.privateMessageAuthor(nickname)
			}
			message += NotificationStrings.Spoken.separator
		}
		return message + text
	}

	@MainActor
	private func formatSpokenChannelEvent(
		_ event: TXNotificationType,
		channel: IRCChannel?,
		nickname: String?,
		text: String?
	) -> String? {
		guard let channel, let nickname, let text, !text.isEmpty else { return nil }
		let visibility = IRCSpokenNotificationPolicy.channelMessageVisibility(
			onlySpeakSelection: TextualPreferences.onlySpeakEventsForSelection(),
			channelIsSelected: isSelected(channel),
			includeConfiguredChannelName: TextualPreferences.channelMessageSpeakChannelName(),
			includeConfiguredNickname: TextualPreferences.channelMessageSpeakNickname()
		)
		guard visibility.shouldSpeak else { return nil }

		var message = ""
		if visibility.includesChannelName || visibility.includesNickname {
			message += event == .channelMessage
				? NotificationStrings.Spoken.channelMessage
				: NotificationStrings.Spoken.channelNotice
			if visibility.includesChannelName {
				message += NotificationStrings.Spoken.channel(spokenChannelName(channel))
			}
			if visibility.includesNickname {
				message += NotificationStrings.Spoken.author(nickname)
			}
			message += NotificationStrings.Spoken.separator
		}
		return message + text
	}

	private func formatSpokenPrivateEvent(
		_ event: TXNotificationType,
		nickname: String?,
		text: String?
	) -> String? {
		guard let nickname, let text, !text.isEmpty else { return nil }
		return NotificationStrings.Spoken.privateMessage(for: event, from: nickname, text: text)
	}

	@MainActor
	private func formatSpokenKick(channel: IRCChannel?, nickname: String?) -> String? {
		guard let channel, let nickname else { return nil }
		return NotificationStrings.Spoken.kicked(from: spokenChannelName(channel), by: nickname)
	}

	private func formatSpokenInvite(nickname: String?, channelName: String?) -> String? {
		guard let nickname, let channelName else { return nil }
		let nameWithoutBang = (channelName as NSString).channelNameWithoutBang ?? channelName
		return NotificationStrings.Spoken.invited(to: nameWithoutBang, by: nickname)
	}

	private func formatSpokenFileTransfer(_ event: TXNotificationType, nickname: String?) -> String? {
		guard let nickname else { return nil }
		return NotificationStrings.Spoken.fileTransfer(for: event, with: nickname)
	}

	@MainActor
	private func formatSpokenMembership(
		_ event: TXNotificationType,
		channel: IRCChannel?,
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
		if !TextualPreferences.removeAllFormatting() {
			text = (text as NSString).stripIRCEffects
		}
		return text
	}

	@MainActor
	private func spokenChannelName(_ channel: IRCChannel) -> String {
		(channel.name as NSString).channelNameWithoutBang ?? channel.name
	}

	@MainActor
	private func isSelected(_ channel: IRCChannel?) -> Bool {
		guard let treeItem = (channel as AnyObject?) as? IRCTreeItem else { return false }
		return AppController.shared.mainWindow?.isItemSelected(treeItem) ?? false
	}

	@objc func clearEventsToSpeak() {
		SharedApplication.sharedSpeechSynthesizer().clearQueue(for: self)
	}

	@objc(speakEvent:lineType:target:nickname:text:)
	func speakEvent(
		_ event: TXNotificationType,
		lineType: TVCLogLineType,
		target: IRCTreeItem?,
		nickname: String?,
		text: String?
	) {
		let resolvedTarget = target ?? self
		let channel = (resolvedTarget as AnyObject) as? IRCChannel
		guard SharedApplication.sharedNotificationController().speakEvent(event, in: channel) else { return }
		let notification = SpokenNotification(
			notificationType: event,
			lineType: lineType,
			target: resolvedTarget,
			nickname: nickname,
			text: text
		)
		/* Formatting reads the client and the channel, so it happens here rather
		 than on the synthesizer's queue. */
		notification.spokenText = formatSpokenNotification(notification)
		SharedApplication.sharedSpeechSynthesizer().speak(notification)
	}

	@objc(notifyText:lineType:target:nickname:text:)
	func notifyText(
		_ event: TXNotificationType,
		lineType: TVCLogLineType,
		target: IRCChannel,
		nickname: String,
		text: String
	) -> Bool {
		notifyEvent(event, lineType: lineType, target: target, nickname: nickname, text: text, userInfo: nil)
	}

	@objc(notifyEvent:lineType:)
	func notifyEvent(_ event: TXNotificationType, lineType: TVCLogLineType) -> Bool {
		notifyEvent(event, lineType: lineType, target: nil, nickname: nil, text: nil, userInfo: nil)
	}

	@objc(notifyEvent:lineType:target:nickname:text:)
	func notifyEvent(
		_ event: TXNotificationType,
		lineType: TVCLogLineType,
		target: IRCChannel?,
		nickname: String?,
		text: String?
	) -> Bool {
		notifyEvent(event, lineType: lineType, target: target, nickname: nickname, text: text, userInfo: nil)
	}

	@objc(notifyEvent:lineType:target:nickname:text:userInfo:)
	func notifyEvent(
		_ event: TXNotificationType,
		lineType: TVCLogLineType,
		target: IRCChannel?,
		nickname: String?,
		text: String?,
		userInfo: [String: Any]?
	) -> Bool {
		deliverNotification(
			event,
			lineType: lineType,
			target: target,
			nickname: nickname,
			text: text,
			userInfo: userInfo
		)
	}

	@MainActor
	private func deliverNotification(
		_ event: TXNotificationType,
		lineType: TVCLogLineType,
		target: IRCChannel?,
		nickname: String?,
		text: String?,
		userInfo suppliedUserInfo: [String: Any]?
	) -> Bool {
		let outputIsSuppressed = if let target, let text {
			outputRuleMatched(in: text, channel: target)
		} else {
			false
		}
		let admission = IRCNotificationPolicy.admission(for: IRCNotificationAdmissionContext(
			event: event,
			isTerminating: isTerminating,
			isCollapsingNetsplit: collapsedNetsplitBatch != nil,
			nicknameIsLocalUser: nickname.map(nicknameIsMyself) ?? false,
			outputIsSuppressed: outputIsSuppressed,
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
		let postWhileFocused = TextualPreferences.postNotificationsWhileInFocus()
		let targetIsSelected = isSelected(target)
		let onlySpeak = IRCNotificationPolicy.shouldOnlySpeak(
			postWhileFocused: postWhileFocused,
			mainWindowIsFocused: mainWindowIsFocused,
			targetIsSelected: targetIsSelected
		)

		if !TextualPreferences.soundIsMuted() {
			if !onlySpeak, let soundName = controller.sound(forEvent: event, in: target) {
				SoundPlayer.playAlertSound(soundName)
			}
			let speechTarget = (target as AnyObject?) as? IRCTreeItem
			speakEvent(event, lineType: lineType, target: speechTarget, nickname: nickname, text: text)
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

		controller.notify(
			event,
			title: content.title,
			description: content.description,
			userInfo: userInfo
		)
		return true
	}

	@MainActor
	private func notificationContent(
		for event: TXNotificationType,
		lineType: TVCLogLineType,
		target: IRCChannel?,
		nickname: String?,
		text: String?
	) -> (title: String?, description: String?)? {
		switch event {
		case .highlight, .newPrivateMessage, .channelMessage, .channelNotice, .privateMessage, .privateNotice:
			return textNotificationContent(
				for: event,
				lineType: lineType,
				target: target,
				nickname: nickname,
				text: text
			)

		case .fileTransferSendSuccessful, .fileTransferReceiveSuccessful, .fileTransferSendFailed,
		     .fileTransferReceiveFailed, .fileTransferReceiveRequested:
			return fileTransferNotificationContent(nickname: nickname, text: text)

		case .connect, .disconnect:
			return (networkNameAlt, nil)

		case .addressBookMatch:
			return text.map { (nil, $0) }

		case .kick, .invite, .userJoined, .userParted, .userDisconnected:
			return membershipNotificationContent(
				for: event,
				target: target,
				nickname: nickname,
				text: text
			)

		@unknown default:
			return nil
		}
	}

	@MainActor
	private func textNotificationContent(
		for event: TXNotificationType,
		lineType: TVCLogLineType,
		target: IRCChannel?,
		nickname: String?,
		text: String?
	) -> (title: String?, description: String?)? {
		guard let nickname, let text else { return nil }
		let title: String? = switch event {
		case .highlight, .channelMessage, .channelNotice: target?.name
		default: nil
		}
		let formattedNickname = formatNickname(nickname, in: target)
		return (title, IRCNotificationPolicy.textEventDescription(
			lineType: lineType,
			nickname: nickname,
			formattedNickname: formattedNickname,
			text: text
		))
	}

	private func fileTransferNotificationContent(
		nickname: String?,
		text: String?
	) -> (title: String?, description: String?)? {
		guard let nickname, let text else { return nil }
		return (nickname, text)
	}

	private func membershipNotificationContent(
		for event: TXNotificationType,
		target: IRCChannel?,
		nickname: String?,
		text: String?
	) -> (title: String?, description: String?)? {
		guard let nickname else { return nil }
		let description: String?

		switch event {
		case .kick:
			guard let target, let text else { return nil }
			description = NotificationStrings.Membership.kicked(
				by: nickname,
				from: target.name,
				reason: text
			)
		case .invite:
			guard let text else { return nil }
			description = NotificationStrings.Membership.invited(by: nickname, to: text)
		case .userJoined:
			guard let target else { return nil }
			description = NotificationStrings.Membership.joined(nickname: nickname, channelName: target.name)
		case .userParted:
			guard let target else { return nil }
			description = NotificationStrings.Membership.parted(
				nickname: nickname,
				channelName: target.name,
				reason: text
			)
		case .userDisconnected:
			description = NotificationStrings.Membership.disconnected(nickname: nickname, reason: text)
		default:
			return nil
		}

		return (networkNameAlt, description)
	}
}
