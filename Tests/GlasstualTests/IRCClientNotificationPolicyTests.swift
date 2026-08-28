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
@testable import Glasstual
import Testing

@MainActor
@Suite("Notification policy")
struct IRCClientNotificationPolicyTests {
	@Test("A terminating client and a collapsed netsplit discard the event")
	func admissionDiscardsTerminatingAndCollapsedNetsplitEvents() {
		#expect(admission(event: .highlight, terminating: true) == .discard)
		#expect(admission(event: .userJoined, collapsingNetsplit: true) == .discard)
		#expect(admission(event: .userDisconnected, collapsingNetsplit: true) == .discard)
		#expect(admission(event: .userParted, collapsingNetsplit: true) == .proceed)
	}

	@Test("Our own text and suppressed output are discarded, but our own kick is not")
	func admissionDiscardsLocalTextAndSuppressedOutput() {
		#expect(admission(event: .channelMessage, nicknameIsLocalUser: true) == .discard)
		#expect(admission(event: .kick, nicknameIsLocalUser: true) == .proceed)
		#expect(admission(event: .privateMessage, outputIsSuppressed: true) == .discard)
	}

	@Test("A target that ignores highlights or disables push has handled the event itself")
	func admissionTreatsChannelPreferencesAsHandled() {
		#expect(admission(event: .highlight, ignoresHighlights: true) == .handled)
		#expect(admission(event: .channelMessage, disablesPush: true) == .handled)
		#expect(admission(event: .highlight, disablesPush: true) == .proceed)
	}

	@Test("An event for the selected target in a focused window is spoken, not posted")
	func focusedSelectedTargetBecomesSpeechOnly() {
		#expect(IRCNotificationPolicy.shouldOnlySpeak(
			postWhileFocused: true,
			mainWindowIsFocused: true,
			targetIsSelected: true
		))
		#expect(IRCNotificationPolicy.shouldOnlySpeak(
			postWhileFocused: false,
			mainWindowIsFocused: true,
			targetIsSelected: true
		) == false)
	}

	@Test("An address book match posts while focused, and away silences a highlight")
	func postingPolicyPreservesAddressBookFocusExceptionAndAwayPreference() {
		#expect(shouldPost(event: .channelMessage, postWhileFocused: false, focused: true) == false)
		#expect(shouldPost(event: .addressBookMatch, postWhileFocused: false, focused: true))
		#expect(shouldPost(event: .highlight, disabledWhileAway: true, userIsAway: true) == false)
		#expect(shouldPost(event: .highlight, enabled: false) == false)
	}

	@Test("The channel identifier is carried only when there is a channel")
	func notificationUserInfoIncludesChannelOnlyWhenPresent() {
		let clientOnly = IRCNotificationPolicy.notificationUserInfo(
			clientIdentifier: "client",
			channelIdentifier: nil
		)

		#expect(clientOnly[NotificationPayload.clientIdentifierKey] as? String == "client")
		#expect(clientOnly[NotificationPayload.channelIdentifierKey] == nil)

		let channel = IRCNotificationPolicy.notificationUserInfo(
			clientIdentifier: "client",
			channelIdentifier: "channel"
		)

		#expect(channel[NotificationPayload.channelIdentifierKey] as? String == "channel")
	}

	@Test("Speaking only the selection silences an unselected channel and drops its name")
	func spokenChannelMessagesRespectSelectionPreference() {
		let hidden = IRCSpokenNotificationPolicy.channelMessageVisibility(
			onlySpeakSelection: true,
			channelIsSelected: false,
			includeConfiguredChannelName: true,
			includeConfiguredNickname: true
		)

		#expect(hidden.shouldSpeak == false)

		let selected = IRCSpokenNotificationPolicy.channelMessageVisibility(
			onlySpeakSelection: true,
			channelIsSelected: true,
			includeConfiguredChannelName: true,
			includeConfiguredNickname: true
		)

		#expect(selected.shouldSpeak)
		#expect(selected.includesChannelName == false)
		#expect(selected.includesNickname)
	}

	@Test("A highlight in an unselected channel is named when selection speech is on")
	func highlightVisibilityIncludesUnselectedChannelWhenSelectionSpeechIsEnabled() {
		let visibility = IRCSpokenNotificationPolicy.highlightVisibility(
			isChannel: true,
			onlySpeakSelection: true,
			channelIsSelected: false,
			includeConfiguredChannelName: false,
			includeConfiguredNickname: false
		)

		#expect(visibility.includesChannelName)
		#expect(visibility.includesNickname == false)
	}

	private func admission(
		event: TXNotificationType,
		terminating: Bool = false,
		collapsingNetsplit: Bool = false,
		nicknameIsLocalUser: Bool = false,
		outputIsSuppressed: Bool = false,
		ignoresHighlights: Bool = false,
		disablesPush: Bool = false
	) -> IRCNotificationAdmission {
		IRCNotificationPolicy.admission(for: IRCNotificationAdmissionContext(
			event: event,
			isTerminating: terminating,
			isCollapsingNetsplit: collapsingNetsplit,
			nicknameIsLocalUser: nicknameIsLocalUser,
			outputIsSuppressed: outputIsSuppressed,
			targetIgnoresHighlights: ignoresHighlights,
			targetDisablesPush: disablesPush
		))
	}

	private func shouldPost(
		event: TXNotificationType,
		enabled: Bool = true,
		postWhileFocused: Bool = true,
		focused: Bool = false,
		disabledWhileAway: Bool = false,
		userIsAway: Bool = false
	) -> Bool {
		IRCNotificationPolicy.shouldPostUserNotification(
			event: event,
			notificationEnabled: enabled,
			postWhileFocused: postWhileFocused,
			mainWindowIsFocused: focused,
			disabledWhileAway: disabledWhileAway,
			userIsAway: userIsAway
		)
	}
}
