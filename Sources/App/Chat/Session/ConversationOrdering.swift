// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/// The order requested by the conversation-sort command.
enum ConversationOrdering {
	static func channelsFirst(_ lhs: Conversation, _ rhs: Conversation) -> Bool {
		if lhs.isChannel != rhs.isChannel {
			return lhs.isChannel
		}
		return lhs.name.lowercased().compare(rhs.name.lowercased()) == .orderedAscending
	}
}
