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

/** A validated IRC nickname, username, and address tuple. */
public struct IRCHostmask: Equatable, Sendable {
	public let nickname: String
	public let username: String
	public let address: String

	public init?(parsing value: String, maximumNicknameLength: Int = 50) {
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

	public static func isValidNickname(_ value: String, maximumLength: Int = 50) -> Bool {
		let source = value as NSString
		return value != "*"
			&& source.length > 0
			&& source.length <= maximumLength
			&& source.containsHostmaskForbiddenCharacters(includingSeparators: true) == false
	}

	public static func isValidUsername(_ value: String) -> Bool {
		let source = value as NSString
		return source.length > 0
			&& source.length <= 40
			&& source.containsHostmaskForbiddenCharacters(includingSeparators: false) == false
	}

	public static func isValidAddress(_ value: String) -> Bool {
		let source = value as NSString
		return source.length > 0
			&& source.containsHostmaskForbiddenCharacters(includingSeparators: true) == false
	}
}

private extension NSString {
	func containsHostmaskForbiddenCharacters(includingSeparators: Bool) -> Bool {
		var forbiddenCharacters: Set<unichar> = [0x00, 0x0A, 0x0D, 0x20]
		if includingSeparators {
			forbiddenCharacters.formUnion([0x21, 0x40])
		}

		return (0 ..< length).contains { forbiddenCharacters.contains(character(at: $0)) }
	}
}
