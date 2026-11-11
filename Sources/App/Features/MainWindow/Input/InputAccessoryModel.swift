// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Observation

@MainActor
@Observable
final class InputAccessoryModel {
	private(set) var replyMessageIdentifier: String?
	private(set) var replyNickname: String?
	private(set) var replyExcerpt: String?
	/// The member a private reply goes to, from the channel the draft is in
	/// (channel-context). `nil` for a reply in public.
	private(set) var privateRecipient: String?
	private(set) var typingNicknames: [String] = []

	var hasContent: Bool {
		hasReply || typingNicknames.isEmpty == false
	}

	var hasReply: Bool {
		replyMessageIdentifier != nil || privateRecipient != nil
	}

	func showReply(
		toMessageIdentifier messageIdentifier: String,
		nickname: String?,
		excerpt: String?
	) {
		replyMessageIdentifier = messageIdentifier
		replyNickname = nickname
		replyExcerpt = excerpt
		privateRecipient = nil
	}

	/// A reply sent privately to `nickname` from the channel, quoting the
	/// message when there is one to quote.
	func showPrivateReply(to nickname: String, messageIdentifier: String?, excerpt: String?) {
		replyMessageIdentifier = messageIdentifier
		replyNickname = nickname
		replyExcerpt = excerpt
		privateRecipient = nickname
	}

	func hideReply() {
		replyMessageIdentifier = nil
		replyNickname = nil
		replyExcerpt = nil
		privateRecipient = nil
	}

	func setTypingNicknames(_ nicknames: [String]) {
		typingNicknames = nicknames
	}
}
