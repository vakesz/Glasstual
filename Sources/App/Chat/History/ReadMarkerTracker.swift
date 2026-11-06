// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/** Where each conversation's read marker has got to.

 Marking a conversation read is debounced: the user scrolls through several
 conversations in a second and the server only needs the newest point in each.
 The tracker holds what has been sent, what is waiting to be, and the timer
 that sends it. */
struct ReadMarkerTracker {
	/// The newest marker sent per conversation, keyed by conversation identifier.
	var sentDates: [String: Date] = [:]
	/// Markers waiting for the debounce to expire, keyed by conversation identifier.
	var pendingConversations: [String: Date] = [:]
	/// Fires once the debounce window closes, sending what is pending.
	let timer: SessionTimer
}
