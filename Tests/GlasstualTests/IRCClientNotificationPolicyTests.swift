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

@testable import Glasstual
import XCTest

@MainActor
final class IRCClientNotificationPolicyTests: XCTestCase {
	func testAdmissionDiscardsTerminatingAndCollapsedNetsplitEvents() {
		XCTAssertEqual(admission(event: .highlight, terminating: true), .discard)
		XCTAssertEqual(admission(event: .userJoined, collapsingNetsplit: true), .discard)
		XCTAssertEqual(admission(event: .userDisconnected, collapsingNetsplit: true), .discard)
		XCTAssertEqual(admission(event: .userParted, collapsingNetsplit: true), .proceed)
	}

	func testAdmissionDiscardsLocalTextAndSuppressedOutput() {
		XCTAssertEqual(admission(event: .channelMessage, nicknameIsLocalUser: true), .discard)
		XCTAssertEqual(admission(event: .kick, nicknameIsLocalUser: true), .proceed)
		XCTAssertEqual(admission(event: .privateMessage, outputIsSuppressed: true), .discard)
	}

	func testAdmissionTreatsChannelPreferencesAsHandled() {
		XCTAssertEqual(admission(event: .highlight, ignoresHighlights: true), .handled)
		XCTAssertEqual(admission(event: .channelMessage, disablesPush: true), .handled)
		XCTAssertEqual(admission(event: .highlight, disablesPush: true), .proceed)
	}

	func testFocusedSelectedTargetBecomesSpeechOnly() {
		XCTAssertTrue(IRCNotificationPolicy.shouldOnlySpeak(
			postWhileFocused: true,
			mainWindowIsFocused: true,
			targetIsSelected: true
		))
		XCTAssertFalse(IRCNotificationPolicy.shouldOnlySpeak(
			postWhileFocused: false,
			mainWindowIsFocused: true,
			targetIsSelected: true
		))
	}

	func testPostingPolicyPreservesAddressBookFocusExceptionAndAwayPreference() {
		XCTAssertFalse(shouldPost(event: .channelMessage, postWhileFocused: false, focused: true))
		XCTAssertTrue(shouldPost(event: .addressBookMatch, postWhileFocused: false, focused: true))
		XCTAssertFalse(shouldPost(event: .highlight, disabledWhileAway: true, userIsAway: true))
		XCTAssertFalse(shouldPost(event: .highlight, enabled: false))
	}

	func testNotificationUserInfoIncludesChannelOnlyWhenPresent() {
		let clientOnly = IRCNotificationPolicy.notificationUserInfo(
			clientIdentifier: "client",
			channelIdentifier: nil
		)
		XCTAssertEqual(clientOnly[NotificationPayload.clientIdentifierKey] as? String, "client")
		XCTAssertNil(clientOnly[NotificationPayload.channelIdentifierKey])

		let channel = IRCNotificationPolicy.notificationUserInfo(
			clientIdentifier: "client",
			channelIdentifier: "channel"
		)
		XCTAssertEqual(channel[NotificationPayload.channelIdentifierKey] as? String, "channel")
	}

	func testSpokenChannelMessagesRespectSelectionPreference() {
		let hidden = IRCSpokenNotificationPolicy.channelMessageVisibility(
			onlySpeakSelection: true,
			channelIsSelected: false,
			includeConfiguredChannelName: true,
			includeConfiguredNickname: true
		)
		XCTAssertFalse(hidden.shouldSpeak)

		let selected = IRCSpokenNotificationPolicy.channelMessageVisibility(
			onlySpeakSelection: true,
			channelIsSelected: true,
			includeConfiguredChannelName: true,
			includeConfiguredNickname: true
		)
		XCTAssertTrue(selected.shouldSpeak)
		XCTAssertFalse(selected.includesChannelName)
		XCTAssertTrue(selected.includesNickname)
	}

	func testHighlightVisibilityIncludesUnselectedChannelWhenSelectionSpeechIsEnabled() {
		let visibility = IRCSpokenNotificationPolicy.highlightVisibility(
			isChannel: true,
			onlySpeakSelection: true,
			channelIsSelected: false,
			includeConfiguredChannelName: false,
			includeConfiguredNickname: false
		)
		XCTAssertTrue(visibility.includesChannelName)
		XCTAssertFalse(visibility.includesNickname)
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
