// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation
@testable import Glasstual
import Testing

@MainActor
@Suite("Notification policy")
struct UserNotificationPolicyTests {
	@Test("A terminating session and a collapsed netsplit discard the event")
	func admissionDiscardsTerminatingAndCollapsedNetsplitEvents() {
		#expect(admits(event: .highlight, terminating: true) == false)
		#expect(admits(event: .userJoined, collapsingNetsplit: true) == false)
		#expect(admits(event: .userDisconnected, collapsingNetsplit: true) == false)
		#expect(admits(event: .userParted, collapsingNetsplit: true))
	}

	@Test("Our own text is discarded, but our own kick is not")
	func admissionDiscardsLocalText() {
		#expect(admits(event: .channelMessage, nicknameIsLocalUser: true) == false)
		#expect(admits(event: .kick, nicknameIsLocalUser: true))
	}

	/// Muting a conversation is the whole of the per-conversation setting, and
	/// a file transfer belongs to no conversation, so muting cannot silence it.
	@Test("A muted conversation is refused, and a transfer still asks")
	func mutedConversationsAreRefused() {
		#expect(admits(event: .highlight, muted: true) == false)
		#expect(admits(event: .channelMessage, muted: true) == false)
		#expect(admits(event: .fileTransferReceiveRequested, muted: true))
	}

	private func admits(
		event: UserNotificationEvent,
		terminating: Bool = false,
		collapsingNetsplit: Bool = false,
		nicknameIsLocalUser: Bool = false,
		muted: Bool = false
	) -> Bool {
		UserNotificationPolicy.admits(UserNotificationAdmissionContext(
			event: event,
			isTerminating: terminating,
			isCollapsingNetsplit: collapsingNetsplit,
			nicknameIsLocalUser: nicknameIsLocalUser,
			conversationIsMuted: muted
		))
	}
}
