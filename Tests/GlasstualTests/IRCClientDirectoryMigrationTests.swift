/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\\__|\__,_|\__,_|_|
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
import XCTest

@MainActor
final class IRCClientDirectoryMigrationTests: XCTestCase {
	func testUserDirectoryUsesServerCasefolding() {
		let client = GLTTestClient()
		let user = client.findUserOrCreate("Alice")

		XCTAssertTrue(client.findUser("ALICE") === user)
		XCTAssertTrue(client.findUserOrCreate("alice") === user)
		XCTAssertEqual(client.numberOfUsers, 1)
	}

	func testAddingADraftUserStoresThatInstance() {
		let client = GLTTestClient()
		let draftUser = client.draftUser(withNickname: "Alice")
		let storedUser = client.addAndReturn(draftUser)

		XCTAssertTrue(storedUser === draftUser)
		XCTAssertEqual(storedUser.nickname, "Alice")
		XCTAssertTrue(client.findUser("Alice") === storedUser)
		XCTAssertNil(client.findUser("Changed"))
	}

	func testRenamingRekeysTheDirectory() {
		let client = GLTTestClient()
		let originalUser = client.findUserOrCreate("Alice")

		client.rename(originalUser, to: "Bob")

		XCTAssertNil(client.findUser("Alice"))
		XCTAssertEqual(client.findUser("Bob")?.nickname, "Bob")
		XCTAssertEqual(client.numberOfUsers, 1)
	}

	func testRemovingUserUpdatesSnapshotsAndCount() {
		let client = GLTTestClient()
		let alice = client.findUserOrCreate("Alice")
		_ = client.findUserOrCreate("Bob")

		client.remove(alice)

		XCTAssertNil(client.findUser("Alice"))
		XCTAssertEqual(client.userList.map(\.nickname), ["Bob"])
		XCTAssertEqual(client.numberOfUsers, 1)
	}

	func testRemoveAllUsersClearsDirectory() {
		let client = GLTTestClient()
		_ = client.findUserOrCreate("Alice")
		_ = client.findUserOrCreate("Bob")

		client.removeAllUsers()

		XCTAssertTrue(client.userList.isEmpty)
		XCTAssertEqual(client.numberOfUsers, 0)
	}

	@MainActor
	func testChannelDirectoryUsesServerCasefoldingAndDoesNotDuplicate() {
		let client = GLTTestClient()
		let channel = client.findChannelOrCreate("#Chat")

		XCTAssertNotNil(channel)
		XCTAssertTrue(client.findChannel("#CHAT") === channel)
		XCTAssertTrue(client.findChannelOrCreate("#chat") === channel)
		XCTAssertEqual(client.channelList.count, 1)
	}
}
