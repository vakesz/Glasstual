// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation
@testable import Glasstual
import Testing

@MainActor
@Suite("Notification policy")
struct NotificationPolicyTests {
	@Test("A terminating client and a collapsed netsplit discard the event")
	func admissionDiscardsTerminatingAndCollapsedNetsplitEvents() {
		#expect(admission(event: .highlight, terminating: true) == .discard)
		#expect(admission(event: .userJoined, collapsingNetsplit: true) == .discard)
		#expect(admission(event: .userDisconnected, collapsingNetsplit: true) == .discard)
		#expect(admission(event: .userParted, collapsingNetsplit: true) == .proceed)
	}

	@Test("Our own text is discarded, but our own kick is not")
	func admissionDiscardsLocalText() {
		#expect(admission(event: .channelMessage, nicknameIsLocalUser: true) == .discard)
		#expect(admission(event: .kick, nicknameIsLocalUser: true) == .proceed)
	}

	/// Muting a conversation is the whole of the per-conversation setting, and
	/// a file transfer belongs to no conversation, so muting cannot silence it.
	@Test("A muted conversation is quiet, and a transfer still asks")
	func mutedConversationsAreQuiet() {
		#expect(admission(event: .highlight, muted: true) == .quiet)
		#expect(admission(event: .channelMessage, muted: true) == .quiet)
		#expect(admission(event: .fileTransferReceiveRequested, muted: true) == .proceed)
	}

	private func admission(
		event: NotificationEvent,
		terminating: Bool = false,
		collapsingNetsplit: Bool = false,
		nicknameIsLocalUser: Bool = false,
		muted: Bool = false
	) -> NotificationAdmission {
		NotificationPolicy.admission(for: NotificationAdmissionContext(
			event: event,
			isTerminating: terminating,
			isCollapsingNetsplit: collapsingNetsplit,
			nicknameIsLocalUser: nicknameIsLocalUser,
			conversationIsMuted: muted
		))
	}
}
