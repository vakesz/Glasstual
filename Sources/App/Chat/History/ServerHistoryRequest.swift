// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/** One page of scroll-back, as the transcript asks for it.

 A `CHATHISTORY BEFORE` is the only request whose answer a view waits on, so
 these three values and the callback they travel with are what the chat layer
 and the transcript agree on. They sat with the chat-item presentation
 protocol, which every chat item conforms to and only one of them wants. */
struct ServerHistoryRequest: Equatable {
	let id: UUID
	let before: Date
	let oldestLineNumber: String?
	let messageIdentifier: String?

	init(id: UUID, before: Date, oldestLineNumber: String?, messageIdentifier: String? = nil) {
		self.id = id
		self.before = before
		self.oldestLineNumber = oldestLineNumber
		self.messageIdentifier = messageIdentifier
	}
}

/// Whether the server has more to give before this page.
enum ServerHistoryPageExtent {
	case unknown
	/// The server answered with nothing, so this is the start of the history.
	case exhausted
}

final class PendingServerHistoryRequest {
	let request: ServerHistoryRequest
	let label: String?
	let connectionIdentifier: String?
	/** Where the page goes, fixed when the request was made.

	 `presentation` is weak, so it cannot answer this later: a presentation that
	 went away between the request and the reply would silently turn a callback
	 request into a transcript one. */
	let delivery: ServerHistoryDelivery
	weak var conversation: Conversation?
	weak var presentation: (any ServerHistoryPresenting)?
	var cancelled = false
	var timeoutTimer: SessionTimer?

	init(request: ServerHistoryRequest, label: String?, conversation: Conversation, connectionIdentifier: String?,
	     presentation: (any ServerHistoryPresenting)?)
	{
		self.request = request
		self.label = label
		self.conversation = conversation
		self.connectionIdentifier = connectionIdentifier
		self.presentation = presentation
		delivery = presentation == nil ? .transcript : .presentation
	}

	isolated deinit { timeoutTimer?.stop() }
}
