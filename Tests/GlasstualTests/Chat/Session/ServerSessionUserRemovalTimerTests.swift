// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

@testable import Glasstual
import Testing

/** A person who shares no channel with the local user is reaped from the
 directory five minutes after they left the last one, unless something still
 holds them by then. The timer runs on a ``ManualTimerClock``, so no test
 waits. */
@MainActor
@Suite("Server session user removal timer")
struct ServerSessionUserRemovalTimerTests {
	/// Virtual seconds past the five-minute removal interval.
	private static let pastInterval: Double = 400

	private let clock = ManualTimerClock()

	private func makeSession() -> TestServerSession {
		let session = TestServerSession()
		session.userNickname = "me"
		session.userRemovalClock = clock.timerClock
		return session
	}

	private func makeQuery(_ nickname: String, on session: TestServerSession) throws -> Conversation {
		try #require(session.findConversationOrCreate(nickname, as: .direct))
	}

	@Test("Reopening a query stops the timer its closing started")
	func reopenedQueryKeepsItsPeople() async throws {
		let session = makeSession()
		defer { clock.finish() }
		let query = try makeQuery("bob", on: session)
		query.activate()
		let bob = try #require(session.findUser("bob"))

		query.deactivate()
		await clock.advance(by: 60)
		query.activate()
		await clock.advance(by: Self.pastInterval)

		#expect(session.findUser("bob")?.id == bob.id)
		#expect(session.myself != nil)
		#expect(query.memberInfo?.findMember("bob")?.id == bob.id)
	}

	@Test("A closed query's peer is still reaped, and the local user is not")
	func closedQueryPeerIsReaped() async throws {
		let session = makeSession()
		defer { clock.finish() }
		let query = try makeQuery("bob", on: session)
		query.activate()
		let bob = try #require(session.findUser("bob"))

		query.deactivate()
		await clock.advance(by: Self.pastInterval)

		#expect(session.findUser("bob") == nil)
		#expect(session.userStores[bob.id] == nil)
		#expect(session.myself != nil)
	}

	@Test("An open query holds a peer who left the last shared channel, until it closes")
	func openQueryHoldsPeerOutsideChannels() async throws {
		let session = makeSession()
		defer { clock.finish() }
		let channel = try #require(session.findConversationOrCreate("#chan", as: .channel))
		channel.activate()
		channel.addUser(session.findUserOrCreate("bob"))
		let query = try makeQuery("bob", on: session)
		query.activate()
		let bob = try #require(session.findUser("bob"))

		channel.removeMember(withNickname: "bob")
		await clock.advance(by: Self.pastInterval)

		#expect(session.findUser("bob")?.id == bob.id)
		#expect(query.memberInfo?.findMember("bob")?.id == bob.id)

		// The timer that came due left its slot free, so closing starts another.
		query.deactivate()
		await clock.advance(by: Self.pastInterval)

		#expect(session.findUser("bob") == nil)
	}

	@Test("A timer whose person has left the directory drops their store")
	func timerForAbsentPersonDropsTheStore() async throws {
		let session = makeSession()
		defer { clock.finish() }
		let query = try makeQuery("bob", on: session)
		query.activate()
		let bob = try #require(session.findUser("bob"))
		query.deactivate()
		#expect(session.userStores[bob.id] != nil)

		session.removeUser(withNickname: "bob")
		await clock.advance(by: Self.pastInterval)

		#expect(session.userStores[bob.id] == nil)
	}
}
