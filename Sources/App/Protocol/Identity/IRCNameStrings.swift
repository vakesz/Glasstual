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
 *********************************************************************** */

import CocoaExtensions
import Foundation
import GlasstualPluginKit

/// The longest nickname to read out of a hostmask before ISUPPORT says
/// otherwise. RFC 2812 fixes no ceiling and servers differ, so this is the
/// widest any network is known to allow.
private nonisolated let defaultHostmaskNicknameLength = 50 // nonisolated: let

@MainActor
private func maximumHostmaskNicknameLength(on client: IRCClient?) -> Int {
	guard let client, client.isConnectedToZNC == false, client.supportInfo.configurationReceived else {
		return defaultHostmaskNicknameLength
	}

	let configuredMaximum = Int(client.supportInfo.maximumNicknameLength)
	return configuredMaximum > 0 ? configuredMaximum : defaultHostmaskNicknameLength
}

/** The string-level questions the protocol layer asks about a name.

 Every one of these reads a name the server sent or the user typed and says
 what kind of name it is, or takes it apart. The forms that take a client ask
 the narrower question the connection can answer from ISUPPORT; the ones
 without ask what the grammar alone allows. */
public nonisolated extension NSString { // nonisolated: pure
	var isValidInternetAddress: Bool {
		guard length > 0 else {
			return false
		}

		if (self as String).isIPAddress || isEqual(to: "localhost") {
			return true
		}

		return (self as String).onlyContainsCharacters(from: .textualAlphanumericDashPeriod)
	}

	var isValidInternetPort: Bool {
		guard let value = Int(self as String) else {
			return false
		}

		return value.isValidInternetPort
	}

	/// The receiver parsed as `nickname!username@address`, or `nil` when it is
	/// not a hostmask. Nickname length is bounded by the protocol default.
	var hostmask: IRCHostmask? {
		IRCHostmask(parsing: self as String, maximumNicknameLength: defaultHostmaskNicknameLength)
	}

	/// The receiver parsed as a hostmask, bounding the nickname by whatever
	/// length `client` advertised in its ISUPPORT.
	@MainActor
	func hostmask(on client: IRCClient?) -> IRCHostmask? {
		IRCHostmask(
			parsing: self as String,
			maximumNicknameLength: maximumHostmaskNicknameLength(on: client)
		)
	}

	/// The receiver read as an RFC 2812 2.3.1 message prefix, or `nil` when it
	/// names a server rather than a user.
	@MainActor
	func senderPrefix(on client: IRCClient?) -> Prefix? {
		Prefix.user(
			parsing: self as String,
			maximumNicknameLength: maximumHostmaskNicknameLength(on: client)
		)
	}

	var isHostmask: Bool {
		hostmask != nil
	}

	/// Whether the receiver could be the address half of a hostmask. RFC 2812
	/// 2.3.1 fixes what that may contain and no ISUPPORT token widens it, so
	/// there is nothing for the connection to say.
	var isHostmaskAddress: Bool {
		IRCHostmask.isValidAddress(self as String)
	}

	/// Whether the receiver could be the username half of a hostmask. Fixed by
	/// the grammar, like the address.
	var isHostmaskUsername: Bool {
		IRCHostmask.isValidUsername(self as String)
	}

	var isHostmaskNickname: Bool {
		IRCHostmask.isValidNickname(self as String, maximumLength: defaultHostmaskNicknameLength)
	}

	@MainActor
	func isHostmaskNickname(on client: IRCClient?) -> Bool {
		IRCHostmask.isValidNickname(
			self as String,
			maximumLength: maximumHostmaskNicknameLength(on: client)
		)
	}

	@MainActor
	func isChannelName(on client: IRCClient) -> Bool {
		guard length > 0 else {
			return false
		}

		let channelNamePrefixes = client.supportInfo.channelNamePrefixes
		let channelName = self as String
		let firstCharacter = String(channelName.prefix(1))

		return channelName.hasPrefix("~#") || channelNamePrefixes.contains(firstCharacter)
	}

	/** Whether the name starts with any prefix an IRC network is known to use.

	 This is the syntactic question, for the call sites that have no connection
	 to ask — validating a name the user typed, or one read out of a URL. Once
	 there is a client, `isChannelName(on:)` asks the narrower one the server
	 actually answered with ISUPPORT `CHANTYPES`. */
	var isChannelName: Bool {
		guard length > 0 else {
			return false
		}

		let firstCharacter = character(at: 0)
		return firstCharacter == 0x23 || firstCharacter == 0x26 || firstCharacter == 0x2B
			|| firstCharacter == 0x21 || firstCharacter == 0x7E || firstCharacter == 0x3F
	}

	/// The name with its channel prefix removed, or unchanged when it carries
	/// none.
	var channelNameWithoutPrefix: String {
		guard isChannelName else {
			return self as String
		}

		return substring(from: 1)
	}

	/// The nickname half of a hostmask, or the whole string when it is not one.
	var nicknameFromHostmask: String {
		hostmask?.nickname ?? (self as String)
	}

	func padNickname(withCharacter padCharacter: unichar, maximumLength: UInt) -> String? {
		precondition(padCharacter != 0)
		precondition(maximumLength > 0)

		let padCharacterString = String(utf16CodeUnits: [padCharacter], count: 1)

		if length < Int(maximumLength) {
			return (self as String) + padCharacterString
		}

		let substring = substring(to: Int(maximumLength)) as NSString

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
		guard length == 1 else {
			return false
		}

		guard let scalar = UnicodeScalar(character(at: 0)) else {
			return false
		}

		return CharacterSet.textualLetter.contains(scalar)
	}
}
