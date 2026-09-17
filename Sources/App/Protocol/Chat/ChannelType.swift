// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

/// The kind of IRC conversation represented by a channel model.
///
/// The raw values are persisted in stored channel configurations.
nonisolated enum ChannelType: UInt, CaseIterable, Sendable {
	case channel = 0
	case privateMessage = 1
	case utility = 2
	/// A DCC CHAT session. Direct chats are never persisted.
	case directChat = 3
}

/// The connection lifecycle state of an IRC channel.
nonisolated enum ChannelStatus: UInt, CaseIterable, Sendable {
	case parted = 0
	case joining = 1
	case joined = 2
	case terminated = 3
}
