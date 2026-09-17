// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/** Who sent a message: either a user (nickname!username@address) or the server
 itself. A plain value — callers that need to change a field copy and assign. */
nonisolated struct Prefix: Hashable, Sendable {
	var isServer: Bool
	var hostmask: String
	var nickname: String
	var username: String?
	var address: String?

	init(
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
	static func user(parsing prefix: String, maximumNicknameLength: Int) -> Prefix? {
		if let hostmask = Hostmask(parsing: prefix, maximumNicknameLength: maximumNicknameLength) {
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
			/* `nick!@host`: the username half is empty, which `Hostmask`
			 refuses. The person is still named, and reading the whole string as
			 a server name sent their message to the console instead of to the
			 query with them. A "!" followed by anything else is the fully
			 qualified form `Hostmask` has already rejected, so its username
			 half is unusable and the prefix stays unparsed. */
			guard userSection.index(after: usernameSeparator) == userSection.endIndex else {
				return nil
			}

			nickname = String(userSection[..<usernameSeparator])
		} else {
			nickname = userSection
		}

		guard Hostmask.isValidNickname(nickname, maximumLength: maximumNicknameLength),
		      Hostmask.isValidAddress(address)
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
		      Hostmask.isValidNickname(prefix, maximumLength: maximumNicknameLength)
		else {
			return nil
		}

		return Prefix(nickname: prefix, hostmask: prefix)
	}
}
