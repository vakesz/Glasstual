// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing

/// `draft/no-implicit-names`: the server stops sending the member list after a
/// JOIN, so the session asks for it after its own.
@MainActor
@Suite("No implicit NAMES")
struct ServerSessionNoImplicitNamesTests {
	private func session() -> TestServerSession {
		let session = TestServerSession(configDictionary: ["nickname": "me", "username": "me"])
		session.setConnectionTransportForTesting(.connected)
		session.userNickname = "me"
		session.markAsLoggedIn()
		return session
	}

	private func join(_ channel: String, as nickname: String, replayed: Bool = false, on session: TestServerSession) throws {
		var message = try #require(Message(line: ":\(nickname)!u@h JOIN \(channel)", on: session))
		message.isReplayed = replayed
		session.receiveJoin(message)
	}

	/// A JOIN of ours also asks for the channel modes; only the member-list
	/// requests are this suite's subject.
	private func namesRequests(of session: TestServerSession) -> [String] {
		session.sentLines.compactMap { $0 as? String }.filter { $0.hasPrefix("NAMES") }
	}

	@Test("Our own JOIN requests the member list once the capability is on")
	func ownJoinRequestsNames() throws {
		let session = session()
		session.enableCapability(.noImplicitNames)
		_ = session.findConversationOrCreate("#chan")

		try join("#chan", as: "me", on: session)

		#expect(namesRequests(of: session) == ["NAMES #chan"])
	}

	@Test("Without the capability the server's own NAMES is awaited")
	func ownJoinSendsNothingWithoutTheCapability() throws {
		let session = session()
		_ = session.findConversationOrCreate("#chan")

		try join("#chan", as: "me", on: session)

		#expect(namesRequests(of: session).isEmpty)
	}

	@Test("Somebody else joining does not request the list")
	func otherJoinSendsNothing() throws {
		let session = session()
		session.enableCapability(.noImplicitNames)
		let channel = try #require(session.findConversationOrCreate("#chan"))
		channel.activate()

		try join("#chan", as: "alice", on: session)

		#expect(namesRequests(of: session).isEmpty)
	}

	@Test("A replayed JOIN of ours does not request the list")
	func replayedJoinSendsNothing() throws {
		let session = session()
		session.enableCapability(.noImplicitNames)
		_ = session.findConversationOrCreate("#chan")

		try join("#chan", as: "me", replayed: true, on: session)

		#expect(namesRequests(of: session).isEmpty)
	}
}
