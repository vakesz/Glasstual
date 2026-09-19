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
		#expect(session.numberOfUsers == 1)
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
		#expect(session.numberOfUsers == 1)
	}

	@Test("Removing a user updates the published list and the count")
	func removingUserUpdatesSnapshotsAndCount() {
		let session = TestServerSession()
		let alice = session.findUserOrCreate("Alice")
		_ = session.findUserOrCreate("Bob")

		session.remove(alice)

		#expect(session.findUser("Alice") == nil)
		#expect(session.userList.map(\.nickname) == ["Bob"])
		#expect(session.numberOfUsers == 1)
	}

	@Test("Removing every user empties the directory")
	func removeAllUsersClearsDirectory() {
		let session = TestServerSession()
		_ = session.findUserOrCreate("Alice")
		_ = session.findUserOrCreate("Bob")

		session.removeAllUsers()

		#expect(session.userList.isEmpty)
		#expect(session.numberOfUsers == 0)
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
