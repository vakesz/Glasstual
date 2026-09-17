// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/** A validated IRC nickname, username, and address tuple. */
nonisolated struct Hostmask: Equatable, Sendable {
	let nickname: String
	let username: String
	let address: String

	init?(parsing value: String, maximumNicknameLength: Int = 50) {
		let source = value as NSString
		let nicknameSeparator = source.range(of: "!", options: .literal)

		guard nicknameSeparator.location != NSNotFound else {
			return nil
		}

		// An IRC hostmask delimits on the first "@" after the "!". Searching
		// backwards let "nick!user@host@evil" parse as address "evil", which
		// matches a different address book rule than the operator wrote.
		let searchStart = nicknameSeparator.location + nicknameSeparator.length
		let addressSeparator = source.range(
			of: "@",
			options: .literal,
			range: NSRange(location: searchStart, length: source.length - searchStart)
		)

		guard addressSeparator.location != NSNotFound else {
			return nil
		}

		let nickname = source.substring(to: nicknameSeparator.location)
		let usernameStart = nicknameSeparator.location + 1
		let username = source.substring(
			with: NSRange(location: usernameStart, length: addressSeparator.location - usernameStart)
		)
		let address = source.substring(from: addressSeparator.location + 1)

		guard Self.isValidNickname(nickname, maximumLength: maximumNicknameLength),
		      Self.isValidUsername(username),
		      Self.isValidAddress(address)
		else {
			return nil
		}

		self.nickname = nickname
		self.username = username
		self.address = address
	}

	static func isValidNickname(_ value: String, maximumLength: Int = 50) -> Bool {
		let source = value as NSString
		return value != "*"
			&& source.length > 0
			&& source.length <= maximumLength
			&& source.containsHostmaskForbiddenCharacters(includingSeparators: true) == false
	}

	static func isValidUsername(_ value: String) -> Bool {
		let source = value as NSString
		return source.length > 0
			&& source.length <= 40
			&& source.containsHostmaskForbiddenCharacters(includingSeparators: false) == false
	}

	static func isValidAddress(_ value: String) -> Bool {
		let source = value as NSString
		return source.length > 0
			&& source.containsHostmaskForbiddenCharacters(includingSeparators: true) == false
	}
}

private nonisolated extension NSString {
	func containsHostmaskForbiddenCharacters(includingSeparators: Bool) -> Bool {
		var forbiddenCharacters: Set<unichar> = [0x00, 0x0A, 0x0D, 0x20]
		if includingSeparators {
			forbiddenCharacters.formUnion([0x21, 0x40])
		}

		return (0 ..< length).contains { forbiddenCharacters.contains(character(at: $0)) }
	}
}
