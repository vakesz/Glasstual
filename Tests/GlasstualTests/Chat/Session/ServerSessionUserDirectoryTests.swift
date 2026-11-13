// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

@testable import Glasstual
import Testing

@MainActor
@Suite("Server session user and channel directory")
struct ServerSessionUserDirectoryTests {
	@Test("A user is found under any casing the server considers the same")
	func userDirectoryUsesServerCasefolding() {
		let session = TestServerSession()
		let user = session.findUserOrCreate("Alice")

		#expect(session.findUser("ALICE") == user)
		#expect(session.findUserOrCreate("alice") == user)
		#expect(session.userIndex.count == 1)
	}

	@Test("Adding a draft user stores that very instance")
	func addingADraftUserStoresThatInstance() {
		let session = TestServerSession()
		let draftUser = session.draftUser(withNickname: "Alice")
		let storedUser = session.addAndReturn(draftUser)

		#expect(storedUser == draftUser)
		#expect(storedUser.nickname == "Alice")
		#expect(session.findUser("Alice") == storedUser)
		#expect(session.findUser("Changed") == nil)
	}

	@Test("Renaming a user rekeys the directory")
	func renamingRekeysTheDirectory() {
		let session = TestServerSession()
		let originalUser = session.findUserOrCreate("Alice")

		session.rename(originalUser, to: "Bob")

		#expect(session.findUser("Alice") == nil)
		#expect(session.findUser("Bob")?.nickname == "Bob")
		#expect(session.userIndex.count == 1)
	}

	@Test("Renaming into a nickname a stale person still holds retires that person")
	func renameIntoHeldNicknameRetiresTheHolder() throws {
		let clock = ManualTimerClock()
		defer { clock.finish() }
		let session = TestServerSession()
		session.userNickname = "me"
		session.userRemovalClock = clock.timerClock
		// "bar" wrote once and closed the query, so only a removal timer holds them.
		let query = try #require(session.findConversationOrCreate("bar", as: .direct))
		query.activate()
		let staleBar = try #require(session.findUser("bar"))
		query.deactivate()
		#expect(session.userStores[staleBar.id]?.removeUserTask != nil)
		let channel = try #require(session.findConversationOrCreate("#chan", as: .channel))
		channel.activate()
		let foo = session.findUserOrCreate("foo")
		channel.addUser(foo)

		session.rename(foo, to: "bar")

		#expect(session.findUser("bar")?.id == foo.id)
		#expect(session.findUser("foo") == nil)
		#expect(session.userStores[staleBar.id] == nil)
		#expect(session.userIndex.count == 2)
		#expect(channel.memberInfo?.findMember("bar")?.id == foo.id)
	}

	@Test("A rename that only changes case keeps the person, their store and their channels")
	func caseOnlyRenameKeepsThePerson() throws {
		let session = TestServerSession()
		let channel = try #require(session.findConversationOrCreate("#chan", as: .channel))
		channel.activate()
		let foo = session.findUserOrCreate("foo")
		channel.addUser(foo)
		let store = try #require(session.userStores[foo.id])

		session.rename(foo, to: "FOO")

		let renamed = try #require(session.findUser("foo"))
		#expect(renamed.id == foo.id)
		#expect(renamed.nickname == "FOO")
		#expect(session.userStores[foo.id] === store)
		#expect(session.relatedChannels(of: renamed).contains(channel))
		#expect(channel.memberInfo?.findMember("FOO")?.id == foo.id)
	}

	@Test("An open query named after the retired person passes to the nickname's new holder")
	func openQueryFollowsTheNickname() throws {
		let clock = ManualTimerClock()
		defer { clock.finish() }
		let session = TestServerSession()
		session.userNickname = "me"
		session.userRemovalClock = clock.timerClock
		let query = try #require(session.findConversationOrCreate("bar", as: .direct))
		query.activate()
		let staleBar = try #require(session.findUser("bar"))
		let channel = try #require(session.findConversationOrCreate("#chan", as: .channel))
		channel.activate()
		let foo = session.findUserOrCreate("foo")
		channel.addUser(foo)

		session.rename(foo, to: "bar")

		#expect(query.memberInfo?.findMember("bar")?.id == foo.id)
		#expect(query.memberInfo?.findMember(withUserID: staleBar.id) == nil)
		#expect(session.userStores[staleBar.id] == nil)
		#expect(session.myself.flatMap { query.memberInfo?.findMember(withUserID: $0.id) } != nil)
	}

	@Test("Removing a user updates the published list and the count")
	func removingUserUpdatesSnapshotsAndCount() {
		let session = TestServerSession()
		let alice = session.findUserOrCreate("Alice")
		_ = session.findUserOrCreate("Bob")

		session.remove(alice)

		#expect(session.findUser("Alice") == nil)
		#expect(session.userList.map(\.nickname) == ["Bob"])
		#expect(session.userIndex.count == 1)
	}

	@Test("Removing every user empties the directory")
	func removeAllUsersClearsDirectory() {
		let session = TestServerSession()
		_ = session.findUserOrCreate("Alice")
		_ = session.findUserOrCreate("Bob")

		session.removeAllUsers()

		#expect(session.userList.isEmpty)
		#expect(session.userIndex.count == 0)
	}

	@Test("A channel is found under any casing the server considers the same, and is never duplicated")
	func channelDirectoryUsesServerCasefoldingAndDoesNotDuplicate() {
		let session = TestServerSession()
		let channel = session.findConversationOrCreate("#Chat")

		#expect(channel != nil)
		#expect(session.findConversation("#CHAT") === channel)
		#expect(session.findConversationOrCreate("#chat") === channel)
		#expect(session.conversationList.count == 1)
	}
}
