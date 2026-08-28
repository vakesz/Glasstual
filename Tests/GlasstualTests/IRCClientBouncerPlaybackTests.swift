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

@testable import Glasstual
import XCTest

@MainActor
final class IRCClientBouncerPlaybackTests: XCTestCase {
	func testPlaybackStartsFromBeginningWithoutAnEligibleTimestamp() {
		XCTAssertEqual(
			PlaybackRequestPolicy.command(
				successfulConnects: 1,
				onlyLatestOnFirstConnect: false,
				lastMessageServerTime: 1_700_000_000
			),
			"play * 0"
		)
		XCTAssertEqual(
			PlaybackRequestPolicy.command(
				successfulConnects: 2,
				onlyLatestOnFirstConnect: true,
				lastMessageServerTime: 0
			),
			"play * 0"
		)
	}

	func testPlaybackUsesRoundedServerTimestampAfterReconnect() {
		XCTAssertEqual(
			PlaybackRequestPolicy.command(
				successfulConnects: 2,
				onlyLatestOnFirstConnect: false,
				lastMessageServerTime: 1_700_000_000.6
			),
			"play * 1700000001"
		)
	}

	func testPlaybackCanUseTimestampOnConfiguredFirstConnect() {
		XCTAssertEqual(
			PlaybackRequestPolicy.command(
				successfulConnects: 1,
				onlyLatestOnFirstConnect: true,
				lastMessageServerTime: 42
			),
			"play * 42"
		)
	}

	func testRequestedChatHistoryNeverPostsNotifications() {
		XCTAssertFalse(notificationDecision(isRequestedChatHistory: true))
	}

	func testOrdinaryServerMessagesPostWithoutABouncer() {
		XCTAssertTrue(notificationDecision(isConnectedToBouncer: false))
	}

	func testConfiguredBouncerUsersDoNotPostNotifications() {
		XCTAssertFalse(notificationDecision(
			ignoresBouncerUsers: true,
			channelIsBouncerUser: true
		))
	}

	func testPlaybackBatchDoesNotPostWhenPlaybackIsIgnored() {
		XCTAssertFalse(notificationDecision(
			ignoresPlayback: true,
			supportsBatch: true,
			batchType: "znc.in/playback"
		))
		XCTAssertTrue(notificationDecision(
			ignoresPlayback: true,
			supportsBatch: true,
			batchType: "other"
		))
	}

	func testHistoricFallbackDoesNotPostWithoutBatchSupport() {
		XCTAssertFalse(notificationDecision(
			ignoresPlayback: true,
			supportsBatch: false,
			isHistoric: true
		))
		XCTAssertTrue(notificationDecision(
			ignoresPlayback: true,
			supportsBatch: false,
			isHistoric: false
		))
	}

	func testChannelUnreadPolicyMatchesDockAndTreePreferences() {
		XCTAssertTrue(ChannelUnreadPolicy.incrementsDockUnreadCount(
			isChannel: false,
			displaysPublicMessageCount: false
		))
		XCTAssertFalse(ChannelUnreadPolicy.incrementsDockUnreadCount(
			isChannel: true,
			displaysPublicMessageCount: false
		))
		XCTAssertTrue(ChannelUnreadPolicy.incrementsDockUnreadCount(
			isChannel: true,
			displaysPublicMessageCount: true
		))
		XCTAssertTrue(ChannelUnreadPolicy.refreshesTreeBadge(
			isHighlight: true,
			showsTreeBadgeCount: false
		))
		XCTAssertFalse(ChannelUnreadPolicy.refreshesTreeBadge(
			isHighlight: false,
			showsTreeBadgeCount: false
		))
	}

	private func notificationDecision(
		isRequestedChatHistory: Bool = false,
		isConnectedToBouncer: Bool = true,
		ignoresBouncerUsers: Bool = false,
		channelIsBouncerUser: Bool = false,
		ignoresPlayback: Bool = false,
		supportsBatch: Bool = false,
		batchType: String? = nil,
		isHistoric: Bool = false
	) -> Bool {
		BouncerNotificationPolicy.shouldPost(BouncerNotificationContext(
			isRequestedChatHistory: isRequestedChatHistory,
			isConnectedToBouncer: isConnectedToBouncer,
			ignoresBouncerUsers: ignoresBouncerUsers,
			channelIsBouncerUser: channelIsBouncerUser,
			ignoresPlayback: ignoresPlayback,
			supportsBatch: supportsBatch,
			batchType: batchType,
			isHistoric: isHistoric
		))
	}
}
