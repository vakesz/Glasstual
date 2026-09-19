// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Observation

@MainActor
@Observable
final class InputAccessoryModel {
	private(set) var replyMessageIdentifier: String?
	private(set) var replyNickname: String?
	private(set) var replyExcerpt: String?
	private(set) var typingNicknames: [String] = []

	var hasContent: Bool {
		replyMessageIdentifier != nil || typingNicknames.isEmpty == false
	}

	func showReply(
		toMessageIdentifier messageIdentifier: String,
		nickname: String?,
		excerpt: String?
	) {
		replyMessageIdentifier = messageIdentifier
		replyNickname = nickname
		replyExcerpt = excerpt
	}

	func hideReply() {
		replyMessageIdentifier = nil
		replyNickname = nil
		replyExcerpt = nil
	}

	func setTypingNicknames(_ nicknames: [String]) {
		typingNicknames = nicknames
	}
}
