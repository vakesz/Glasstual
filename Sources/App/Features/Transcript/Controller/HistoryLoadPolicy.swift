// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/** Whether a transcript reads its stored scrollback when it loads.

 The console and one-to-one chats never replay stored lines. On the first load
 of a view the reader's settings decide: scrollback is replayed only when asked
 for, and a direct conversation only when direct conversations are remembered. */
nonisolated struct HistoryLoadPolicy: Sendable, Equatable {
	var firstLoad: Bool
	var reloadsScrollbackOnLaunch: Bool
	var isConsole: Bool
	var isDirectChat: Bool
	var isDirect: Bool
	var remembersDirectConversations: Bool

	var includesStoredHistory: Bool {
		if isConsole || isDirectChat {
			return false
		}
		guard firstLoad else {
			return true
		}
		return reloadsScrollbackOnLaunch && (!isDirect || remembersDirectConversations)
	}
}
