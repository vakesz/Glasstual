// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/// Where a private message that carries a `channel-context` tag is filed.
enum ChannelContextFiling {
	/// In the channel it names, marked as private.
	case channel(Conversation)
	/// In the query as usual, labelled with the channel it names.
	case query(channelName: String)
}

extension ServerSession {
	/** Where a private message's `channel-context` tag files it, or `nil` when
	 it has none worth reading.

	 The line moves to the channel only when the channel is joined, the other
	 party is in it, the setting allows it, and the line is not a page of the
	 query's own history. Anyone can name a channel, so a sender who is not in
	 it only gets the channel named beside the line in the query. */
	func channelContextFiling(for message: Message, peer: String) -> ChannelContextFiling? {
		guard message.remoteCommand == .privmsg || message.remoteCommand == .notice,
		      let channelName = ChannelContextTag.channelName(in: message.messageTags),
		      stringIsChannelName(channelName)
		else { return nil }

		guard environment.settings.showChannelContextMessagesInChannel,
		      let channel = findConversation(channelName), channel.isChannel, channel.isActive,
		      channel.memberInfo?.findMember(peer) != nil,
		      isQueryHistoryPage(message, peer: peer) == false
		else { return .query(channelName: channelName) }

		return .channel(channel)
	}

	private func isQueryHistoryPage(_ message: Message, peer: String) -> Bool {
		guard let batch = batchMessage(ofKind: .chatHistory, containing: message),
		      let target = batch.batchParameters?.first
		else { return false }
		return stringIsChannelName(target) == false && casefoldNickname(target) == casefoldNickname(peer)
	}
}
