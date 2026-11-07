// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing

/// An INVITE naming somebody else is an `invite-notify` event; without the
/// capability it is not one the session asked for.
@MainActor
@Suite("invite-notify gating")
struct ServerSessionInviteNotifyGatingTests {
	private func session() -> TestServerSession {
		let session = TestServerSession(configDictionary: ["nickname": "me", "username": "me"])
		session.userNickname = "me"
		return session
	}

	@Test("An INVITE for another user is not reported without the capability")
	func thirdPartyInviteIsIgnoredWithoutTheCapability() throws {
		let session = session()
		let channel = try #require(session.findConversationOrCreate("#chan"))
		channel.activate()
		let message = try #require(Message(line: ":op!o@example.org INVITE alice #chan", on: session))

		session.receiveInvite(message)

		#expect(session.printedLines.count == 0)
	}

	@Test("An INVITE addressed to us is reported whether or not the capability is on")
	func inviteToUsIsNotGated() throws {
		let session = session()
		let message = try #require(Message(line: ":op!o@example.org INVITE me #elsewhere", on: session))

		session.receiveInvite(message)

		#expect(session.printedLines.count == 1)
	}
}
