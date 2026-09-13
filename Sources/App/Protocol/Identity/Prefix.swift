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

import Foundation
import GlasstualPluginKit

/** Who sent a message: either a user (nickname!username@address) or the server
 itself. A plain value — callers that need to change a field copy and assign. */
public nonisolated struct Prefix: Hashable, Sendable { // nonisolated: value
	public var isServer: Bool
	public var hostmask: String
	public var nickname: String
	public var username: String?
	public var address: String?

	public init(
		nickname: String = "",
		username: String? = nil,
		address: String? = nil,
		hostmask: String = "",
		isServer: Bool = false
	) {
		self.nickname = nickname
		self.username = username
		self.address = address
		self.hostmask = hostmask
		self.isServer = isServer
	}

	/** The user a prefix names, or `nil` when the prefix is a server name.

	 RFC 2812 2.3.1 writes the prefix as

	     prefix = servername / ( nickname [ [ "!" user ] "@" host ] )

	 so the `!user` half is optional: `nick@host` names a user just as
	 `nick!user@host` does, and only a prefix with no `@` at all is a server
	 name. Reading `nick@host` as a server put the whole string in the
	 nickname and filed the message in the console. */
	public static func user(parsing prefix: String, maximumNicknameLength: Int) -> Prefix? {
		if let hostmask = IRCHostmask(parsing: prefix, maximumNicknameLength: maximumNicknameLength) {
			return Prefix(
				nickname: hostmask.nickname,
				username: hostmask.username,
				address: hostmask.address,
				hostmask: prefix
			)
		}

		guard let separator = prefix.firstIndex(of: "@") else {
			return bareNickname(parsing: prefix, maximumNicknameLength: maximumNicknameLength)
		}

		let userSection = String(prefix[..<separator])
		let address = String(prefix[prefix.index(after: separator)...])
		let nickname: String

		if let usernameSeparator = userSection.firstIndex(of: "!") {
			/* `nick!@host`: the username half is empty, which `IRCHostmask`
			 refuses. The person is still named, and reading the whole string as
			 a server name sent their message to the console instead of to the
			 query with them. A "!" followed by anything else is the fully
			 qualified form `IRCHostmask` has already rejected, so its username
			 half is unusable and the prefix stays unparsed. */
			guard userSection.index(after: usernameSeparator) == userSection.endIndex else {
				return nil
			}

			nickname = String(userSection[..<usernameSeparator])
		} else {
			nickname = userSection
		}

		guard IRCHostmask.isValidNickname(nickname, maximumLength: maximumNicknameLength),
		      IRCHostmask.isValidAddress(address)
		else {
			return nil
		}

		return Prefix(nickname: nickname, address: address, hostmask: prefix)
	}

	/** A prefix with no `@` at all, read as the bare `nickname` RFC 2812 2.3.1
	 also allows there.

	 A server relaying a NICK, QUIT or KICK it generated itself may name the
	 person and nothing else, and every such line used to be filed as if the
	 server had sent it: no ignore rule matched, no notification fired, and a
	 query took the whole prefix as its name. A server name is told apart by its
	 dot — the nickname grammar has no `.` in it — so `irc.example.net` stays a
	 server while `alice` becomes a user. */
	private static func bareNickname(parsing prefix: String, maximumNicknameLength: Int) -> Prefix? {
		guard prefix.contains(".") == false, prefix.contains("!") == false,
		      IRCHostmask.isValidNickname(prefix, maximumLength: maximumNicknameLength)
		else {
			return nil
		}

		return Prefix(nickname: prefix, hostmask: prefix)
	}
}
