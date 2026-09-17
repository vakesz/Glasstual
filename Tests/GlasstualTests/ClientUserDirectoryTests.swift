// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

@testable import Glasstual
import Testing

@MainActor
@Suite("Client user and channel directory")
struct ClientUserDirectoryTests {
	@Test("A user is found under any casing the server considers the same")
	func userDirectoryUsesServerCasefolding() {
		let client = TestClient()
		let user = client.findUserOrCreate("Alice")

		#expect(client.findUser("ALICE") == user)
		#expect(client.findUserOrCreate("alice") == user)
		#expect(client.numberOfUsers == 1)
	}

	@Test("Adding a draft user stores that very instance")
	func addingADraftUserStoresThatInstance() {
		let client = TestClient()
		let draftUser = client.draftUser(withNickname: "Alice")
		let storedUser = client.addAndReturn(draftUser)

		#expect(storedUser == draftUser)
		#expect(storedUser.nickname == "Alice")
		#expect(client.findUser("Alice") == storedUser)
		#expect(client.findUser("Changed") == nil)
	}

	@Test("Renaming a user rekeys the directory")
	func renamingRekeysTheDirectory() {
		let client = TestClient()
		let originalUser = client.findUserOrCreate("Alice")

		client.rename(originalUser, to: "Bob")

		#expect(client.findUser("Alice") == nil)
		#expect(client.findUser("Bob")?.nickname == "Bob")
		#expect(client.numberOfUsers == 1)
	}

	@Test("Removing a user updates the published list and the count")
	func removingUserUpdatesSnapshotsAndCount() {
		let client = TestClient()
		let alice = client.findUserOrCreate("Alice")
		_ = client.findUserOrCreate("Bob")

		client.remove(alice)

		#expect(client.findUser("Alice") == nil)
		#expect(client.userList.map(\.nickname) == ["Bob"])
		#expect(client.numberOfUsers == 1)
	}

	@Test("Removing every user empties the directory")
	func removeAllUsersClearsDirectory() {
		let client = TestClient()
		_ = client.findUserOrCreate("Alice")
		_ = client.findUserOrCreate("Bob")

		client.removeAllUsers()

		#expect(client.userList.isEmpty)
		#expect(client.numberOfUsers == 0)
	}

	@Test("A channel is found under any casing the server considers the same, and is never duplicated")
	func channelDirectoryUsesServerCasefoldingAndDoesNotDuplicate() {
		let client = TestClient()
		let channel = client.findChannelOrCreate("#Chat")

		#expect(channel != nil)
		#expect(client.findChannel("#CHAT") === channel)
		#expect(client.findChannelOrCreate("#chat") === channel)
		#expect(client.channelList.count == 1)
	}
}
