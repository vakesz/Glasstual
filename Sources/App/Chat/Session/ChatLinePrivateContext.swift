// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/// How a line labels a private message that belongs to a channel.
nonisolated enum ChatLinePrivateContext: Equatable, Sendable {
	/// Drawn in the channel it belongs to. `peer` is the recipient of one of
	/// our own messages, `nil` for one we received.
	case privatelyInChannel(peer: String?)
	/// Drawn in the query, naming the channel it belongs to.
	case channel(String)

	init?(
		channelContext: String?,
		privatePeer: String?,
		conversationName: String,
		caseMapping: ISupportCaseMapping
	) {
		guard let channelContext else { return nil }
		if IRCCaseFolding.fold(channelContext, using: caseMapping) == IRCCaseFolding.fold(conversationName, using: caseMapping) {
			self = .privatelyInChannel(peer: privatePeer)
		} else {
			self = .channel(channelContext)
		}
	}

	/// The sender column: "nick (privately)", "you → nick (privately)", or
	/// "nick in #channel".
	func sender(_ formattedNickname: String) -> String {
		switch self {
		case let .privatelyInChannel(peer?):
			ChatLineFormat.privateSender(formattedNickname, to: ControlCharacterDisposition.singleLine(peer))
		case .privatelyInChannel(nil):
			ChatLineFormat.privateSender(formattedNickname)
		case let .channel(channel):
			ChatLineFormat.channelContextSender(formattedNickname, channel: ControlCharacterDisposition.singleLine(channel))
		}
	}
}
