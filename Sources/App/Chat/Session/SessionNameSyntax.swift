// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation

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
