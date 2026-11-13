// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

/// What kind of conversation a ``Conversation`` is.
///
/// The raw values are persisted in stored conversation configurations.
nonisolated enum ConversationKind: UInt, CaseIterable, Sendable {
	case channel = 0
	case direct = 1
	case console = 2
	/// A DCC CHAT session. Direct chats are never persisted.
	case directChat = 3
}

/// The lifecycle state of a conversation.
nonisolated enum ConversationStatus: UInt, CaseIterable, Sendable {
	case parted = 0
	case joining = 1
	case joined = 2
	case terminated = 3
}
