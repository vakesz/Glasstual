// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation

/// The longest nickname to read out of a hostmask. RFC 2812 fixes no ceiling
/// and servers differ, so this is the widest any network is known to allow.
nonisolated let defaultHostmaskNicknameLength = 50

/** The longest nickname a name read on `session` may have.

 ISUPPORT `NICKLEN` is how long a nickname the server lets *this* session
 register, and it says nothing binding about the names it relays: services, a
 bouncer's module users and other servers' users across a link routinely exceed
 it. Used as a hard limit, a longer nickname failed to parse as a user and the
 whole prefix was read as a server. So the advertised length only ever widens
 the default, never narrows it. */
@MainActor
func maximumHostmaskNicknameLength(on session: ServerSession?) -> Int {
	let advertised = session?.supportInfo.maximumNicknameLength ?? 0
	return max(Int(clamping: advertised), defaultHostmaskNicknameLength)
}

/** The string-level questions the protocol layer asks about a name.

 Every one of these reads a name the server sent or the user typed and says
 what kind of name it is, or takes it apart. The forms that take a session ask
 the narrower question the connection can answer from ISUPPORT; the ones
 without ask what the grammar alone allows. */
nonisolated extension String { // nonisolated: pure
	var isValidInternetAddress: Bool {
		guard isEmpty == false else {
			return false
		}

		if isIPAddress || self == "localhost" {
			return true
		}

		return onlyContainsCharacters(from: .hostNameCharacters)
	}

	var isValidInternetPort: Bool {
		guard let value = Int(self) else {
			return false
		}

		return value.isValidInternetPort
	}

	/// The receiver parsed as `nickname!username@address`, or `nil` when it is
	/// not a hostmask. Nickname length is bounded by the protocol default.
	var hostmask: Hostmask? {
		Hostmask(parsing: self, maximumNicknameLength: defaultHostmaskNicknameLength)
	}

	var isHostmask: Bool {
		hostmask != nil
	}

	/// Whether the receiver could be the address half of a hostmask. RFC 2812
	/// 2.3.1 fixes what that may contain and no ISUPPORT token widens it, so
	/// there is nothing for the connection to say.
	var isHostmaskAddress: Bool {
		Hostmask.isValidAddress(self)
	}

	/// Whether the receiver could be the username half of a hostmask. Fixed by
	/// the grammar, like the address.
	var isHostmaskUsername: Bool {
		Hostmask.isValidUsername(self)
	}

	var isHostmaskNickname: Bool {
		Hostmask.isValidNickname(self, maximumLength: defaultHostmaskNicknameLength)
	}

	/** Whether the name starts with any prefix an IRC network is known to use.

	 This is the syntactic question, for the call sites that have no connection
	 to ask — validating a name the user typed, or one read out of a URL. Once
	 there is a session, `isChannelName(on:)` asks the narrower one the server
	 actually answered with ISUPPORT `CHANTYPES`. */
	var isChannelName: Bool {
		guard let firstCharacter = utf16.first else {
			return false
		}

		return firstCharacter == 0x23 || firstCharacter == 0x26 || firstCharacter == 0x2B
			|| firstCharacter == 0x21 || firstCharacter == 0x7E || firstCharacter == 0x3F
	}

	/// The nickname half of a hostmask, or the whole string when it is not one.
	var nicknameFromHostmask: String {
		hostmask?.nickname ?? self
	}

	/** The receiver padded out to `maximumLength`, or `nil` when every character
	 it has room for is already the pad character.

	 Lengths are UTF-16 units, the same unit a server counts a nickname in. */
	func padNickname(withCharacter padCharacter: unichar, maximumLength: UInt) -> String? {
		precondition(padCharacter != 0)
		precondition(maximumLength > 0)

		let padCharacterString = String(utf16CodeUnits: [padCharacter], count: 1)
		let string = self as NSString

		if UInt(string.length) < maximumLength {
			return self + padCharacterString
		}

		let substring = string.substring(to: Int(maximumLength)) as NSString

		for i in stride(from: substring.length - 1, through: 0, by: -1) {
			let substringCharacter = substring.character(at: i)

			if substringCharacter == padCharacter {
				continue
			}

			/* The tail used to be hardcoded to "_" while the head branch above
			 used the caller's character. The sole caller passes "_", so the two
			 agreed by accident. */
			var stringHeadMutable = substring.substring(to: i)

			for _ in i ..< substring.length {
				stringHeadMutable += padCharacterString
			}

			return stringHeadMutable
		}

		return nil
	}

	var isModeSymbol: Bool {
		guard utf16.count == 1, let scalar = unicodeScalars.first else {
			return false
		}

		return CharacterSet.asciiLetters.contains(scalar)
	}
}

/** The same questions, narrowed by what one connection advertised.

 Each of these reads ISUPPORT off the session, so none is a pure function of its
 arguments and none belongs in the `nonisolated` extension above. */
extension String {
	/// The receiver parsed as a hostmask, bounding the nickname by whatever
	/// length `session` advertised in its ISUPPORT.
	func hostmask(on session: ServerSession?) -> Hostmask? {
		Hostmask(
			parsing: self,
			maximumNicknameLength: maximumHostmaskNicknameLength(on: session)
		)
	}

	func isHostmaskNickname(on session: ServerSession?) -> Bool {
		Hostmask.isValidNickname(
			self,
			maximumLength: maximumHostmaskNicknameLength(on: session)
		)
	}

	func isChannelName(on session: ServerSession) -> Bool {
		guard isEmpty == false else {
			return false
		}

		let channelNamePrefixes = session.supportInfo.channelNamePrefixes
		let firstCharacter = String(prefix(1))

		return hasPrefix("~#") || channelNamePrefixes.contains(firstCharacter)
	}
}
