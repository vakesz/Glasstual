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

@testable import Glasstual
import Testing

@MainActor
@Suite("Client user and channel directory")
struct IRCClientDirectoryMigrationTests {
	@Test("A user is found under any casing the server considers the same")
	func userDirectoryUsesServerCasefolding() {
		let client = GLTTestClient()
		let user = client.findUserOrCreate("Alice")

		#expect(client.findUser("ALICE") === user)
		#expect(client.findUserOrCreate("alice") === user)
		#expect(client.numberOfUsers == 1)
	}

	@Test("Adding a draft user stores that very instance")
	func addingADraftUserStoresThatInstance() {
		let client = GLTTestClient()
		let draftUser = client.draftUser(withNickname: "Alice")
		let storedUser = client.addAndReturn(draftUser)

		#expect(storedUser === draftUser)
		#expect(storedUser.nickname == "Alice")
		#expect(client.findUser("Alice") === storedUser)
		#expect(client.findUser("Changed") == nil)
	}

	@Test("Renaming a user rekeys the directory")
	func renamingRekeysTheDirectory() {
		let client = GLTTestClient()
		let originalUser = client.findUserOrCreate("Alice")

		client.rename(originalUser, to: "Bob")

		#expect(client.findUser("Alice") == nil)
		#expect(client.findUser("Bob")?.nickname == "Bob")
		#expect(client.numberOfUsers == 1)
	}

	@Test("Removing a user updates the published list and the count")
	func removingUserUpdatesSnapshotsAndCount() {
		let client = GLTTestClient()
		let alice = client.findUserOrCreate("Alice")
		_ = client.findUserOrCreate("Bob")

		client.remove(alice)

		#expect(client.findUser("Alice") == nil)
		#expect(client.userList.map(\.nickname) == ["Bob"])
		#expect(client.numberOfUsers == 1)
	}

	@Test("Removing every user empties the directory")
	func removeAllUsersClearsDirectory() {
		let client = GLTTestClient()
		_ = client.findUserOrCreate("Alice")
		_ = client.findUserOrCreate("Bob")

		client.removeAllUsers()

		#expect(client.userList.isEmpty)
		#expect(client.numberOfUsers == 0)
	}

	@Test("A channel is found under any casing the server considers the same, and is never duplicated")
	func channelDirectoryUsesServerCasefoldingAndDoesNotDuplicate() {
		let client = GLTTestClient()
		let channel = client.findChannelOrCreate("#Chat")

		#expect(channel != nil)
		#expect(client.findChannel("#CHAT") === channel)
		#expect(client.findChannelOrCreate("#chat") === channel)
		#expect(client.channelList.count == 1)
	}
}
