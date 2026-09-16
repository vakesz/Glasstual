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
