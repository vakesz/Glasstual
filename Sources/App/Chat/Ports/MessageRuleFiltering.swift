// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/** Whether the user's message rules let an inbound line be printed.

 The rules themselves are the user's, edited in Settings and stored there; the
 inbound path only asks. Two questions, because a command and a chat line are
 matched on different fields, and both answer `true` when nobody is listening:
 a session with no rule list prints everything it receives. */
@MainActor
protocol MessageRuleFiltering: AnyObject {
	func shouldPrintCommand(
		_ command: String,
		text: String?,
		authoredBy author: Prefix,
		destinedFor destination: Conversation?,
		onSession session: ServerSession,
		receivedAt: Date,
		messageParameters: [String]
	) -> Bool

	func shouldPrintText(
		_ text: String,
		authoredBy author: Prefix,
		destinedFor destination: Conversation?,
		as lineType: ChatLineKind,
		onSession session: ServerSession,
		receivedAt: Date,
		wasEncrypted: Bool
	) -> Bool
}
