/* *********************************************************************
 * Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import Foundation

/// The name questions a connection answers with its own ISUPPORT: whether a
/// name is the local user's, how the server folds it, and what kind of name
/// it is.
public extension IRCClient {
	internal func messageIsFromMyself(_ message: Message) -> Bool {
		nicknameIsMyself(message.senderNickname ?? "")
	}

	func nicknameIsMyself(_ nickname: String) -> Bool {
		casefoldNickname(userNickname) == casefoldNickname(nickname)
	}

	func casefoldNickname(_ nickname: String) -> String {
		supportInfo.casefoldString(nickname)
	}

	func stringIsNickname(_ string: String) -> Bool {
		string.isHostmaskNickname(on: self) && string.isChannelName(on: self) == false
	}

	func stringIsChannelName(_ string: String) -> Bool {
		string.isChannelName(on: self)
	}

	internal func stringIsChannelNameOrZero(_ string: String) -> Bool {
		stringIsChannelName(string) || string == "0"
	}
}
