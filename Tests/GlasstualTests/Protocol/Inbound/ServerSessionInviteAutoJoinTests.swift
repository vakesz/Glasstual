// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing

@MainActor
struct ServerSessionInviteAutoJoinTests {
	private static let autoJoinKey = SettingsKeys.Connection.autojoinOnInvite.name

	private func withAutoJoinOnInvite(_ body: () throws -> Void) rethrows {
		let defaults = GlasstualUserDefaults.container
		let original = defaults.bool(forKey: Self.autoJoinKey)

		defaults.set(true, forKey: Self.autoJoinKey)
		defer { defaults.set(original, forKey: Self.autoJoinKey) }

		try body()
	}

	private func loggedInSession() -> TestServerSession {
		let session = TestServerSession()
		session.userNickname = "mynick"
		session.markAsLoggedIn()
		return session
	}

	private func sentLines(of session: TestServerSession) -> [String] {
		(session.sentLines as NSArray).compactMap { $0 as? String }
	}

	/// `JOIN 0` parts every channel, and anybody may send an INVITE.
	@Test
	func inviteToZeroIsNotAutoJoined() throws {
		try withAutoJoinOnInvite {
			let session = loggedInSession()
			let message = try #require(Message(line: ":evil!u@h INVITE mynick 0", on: session))

			session.receiveInvite(message)

			#expect(sentLines(of: session).contains { $0.hasPrefix("JOIN") } == false)
		}
	}

	@Test
	func inviteToANonChannelNameIsNotAutoJoined() throws {
		try withAutoJoinOnInvite {
			let session = loggedInSession()
			let message = try #require(Message(line: ":evil!u@h INVITE mynick notachannel", on: session))

			session.receiveInvite(message)

			#expect(sentLines(of: session).contains { $0.hasPrefix("JOIN") } == false)
		}
	}

	@Test
	func inviteToARealChannelIsStillAutoJoined() throws {
		try withAutoJoinOnInvite {
			let session = loggedInSession()
			let message = try #require(Message(line: ":friend!u@h INVITE mynick #room", on: session))

			session.receiveInvite(message)

			#expect(sentLines(of: session).contains { $0.hasPrefix("JOIN #room") })
		}
	}

	/// The user typing `/join 0` deliberately is a different path and keeps
	/// working.
	@Test
	func explicitJoinZeroStillWorks() {
		let session = loggedInSession()

		session.joinUnlistedChannel("0", password: nil)

		#expect(sentLines(of: session).contains { $0.hasPrefix("JOIN 0") })
	}
}
