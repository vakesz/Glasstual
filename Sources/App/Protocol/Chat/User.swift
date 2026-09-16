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

import CocoaExtensions
import Foundation

/** Someone visible to this client.

 A value. `id` is the person: it is minted once, when the client first sees the
 nickname, and travels through every edit and every rename, so a copy taken to
 be edited and handed back to the directory still names the same person. The
 state that belongs to the person rather than to this snapshot of them -- which
 channels they are in, the away-message clock, the removal timer -- lives in the
 client's `UserPersistentStore` for that `id`.

 Editing means taking a copy, editing that, and handing it back to the directory
 (`Client.modify(_:block:)`), which relinks the channels the person is in. */
nonisolated struct User: Identifiable, Hashable, Sendable, CustomStringConvertible { // nonisolated: value
	/// The person, stable across renames and edits.
	let id: UUID

	var nickname: String
	var username: String?
	var address: String?
	var realName: String?
	var account: String?
	var isAway = false
	var isIRCop = false
	var isBot = false

	init(nickname: String) {
		id = UUID()
		self.nickname = nickname
	}

	/// A user with a caller-supplied identity. Only the directory and its tests
	/// pick an `id`; everyone else takes a copy of an existing user.
	init(id: UUID, nickname: String) {
		self.id = id
		self.nickname = nickname
	}

	var hostmaskFragment: String? {
		guard let username, let address else {
			return nil
		}

		return "\(username)@\(address)"
	}

	var hostmask: String? {
		guard let username, let address else {
			return nil
		}

		return "\(nickname)!\(username)@\(address)"
	}

	/// The ban mask the preference asks for. The format is passed in because a
	/// user does not know its client; `Client.banMask(for:)` reads it.
	func banMask(format: HostmaskBanFormat) -> String {
		guard let username, let address else {
			return "\(nickname)!*@*"
		}

		switch format {
		case .whnin:
			return "*!*@\(address)"
		case .whainn:
			return "*!\(username)@\(address)"
		case .whanni:
			return "\(nickname)!*@\(address)"
		case .exact:
			return "\(nickname)!\(username)@\(address)"
		@unknown default:
			return "\(nickname)!*@*"
		}
	}

	mutating func markAsAway() {
		isAway = true
	}

	mutating func markAsReturned() {
		isAway = false
	}

	var description: String {
		"<User \(nickname)>"
	}
}
