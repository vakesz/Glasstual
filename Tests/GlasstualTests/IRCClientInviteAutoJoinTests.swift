/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \\ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\\___/_/\\_\\__|\\__,_|\\__,_|_|
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

import Foundation
@testable import Glasstual
import Testing

@MainActor
struct IRCClientInviteAutoJoinTests {
	private static let autoJoinKey = "AutojoinChannelOnInvite"

	private func withAutoJoinOnInvite(_ body: () throws -> Void) rethrows {
		let defaults = TextualUserDefaults.shared()
		let original = defaults.bool(forKey: Self.autoJoinKey)

		defaults.set(true, forKey: Self.autoJoinKey)
		defer { defaults.set(original, forKey: Self.autoJoinKey) }

		try body()
	}

	private func loggedInClient() -> GLTTestClient {
		let client = GLTTestClient()
		client.userNickname = "mynick"
		client.markAsLoggedIn()
		return client
	}

	private func sentLines(of client: GLTTestClient) -> [String] {
		(client.sentLines as NSArray).compactMap { $0 as? String }
	}

	/// `JOIN 0` parts every channel, and anybody may send an INVITE.
	@Test
	func inviteToZeroIsNotAutoJoined() throws {
		try withAutoJoinOnInvite {
			let client = loggedInClient()
			let message = try #require(Message(line: ":evil!u@h INVITE mynick 0", on: client))

			client.receiveInvite(message)

			#expect(sentLines(of: client).contains { $0.hasPrefix("JOIN") } == false)
		}
	}

	@Test
	func inviteToANonChannelNameIsNotAutoJoined() throws {
		try withAutoJoinOnInvite {
			let client = loggedInClient()
			let message = try #require(Message(line: ":evil!u@h INVITE mynick notachannel", on: client))

			client.receiveInvite(message)

			#expect(sentLines(of: client).contains { $0.hasPrefix("JOIN") } == false)
		}
	}

	@Test
	func inviteToARealChannelIsStillAutoJoined() throws {
		try withAutoJoinOnInvite {
			let client = loggedInClient()
			let message = try #require(Message(line: ":friend!u@h INVITE mynick #room", on: client))

			client.receiveInvite(message)

			#expect(sentLines(of: client).contains { $0.hasPrefix("JOIN #room") })
		}
	}

	/// The user typing `/join 0` deliberately is a different path and keeps
	/// working.
	@Test
	func explicitJoinZeroStillWorks() {
		let client = loggedInClient()

		client.joinUnlistedChannel("0", password: nil)

		#expect(sentLines(of: client).contains { $0.hasPrefix("JOIN 0") })
	}
}
