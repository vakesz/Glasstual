// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

enum ServerHistoryOutcome {
	case page(lines: [ChatLine], extent: ServerHistoryPageExtent)
	case failed(reason: String?)
	case cancelled
}

/// Optional capability of a transcript presentation, not of every chat item.
@MainActor
protocol ServerHistoryPresenting: AnyObject {
	func receiveServerHistory(_ outcome: ServerHistoryOutcome, for request: ServerHistoryRequest)
}

/// Whether a conversation is missing messages the server still has, for the
/// banner the transcript draws over it.
enum MissingServerHistoryState: Equatable {
	case none
	case missing
	case loading
	case failed(reason: String?)
}

/// Where the page a `CHATHISTORY BEFORE` brings back is delivered.
enum ServerHistoryDelivery {
	/// The session prepends the lines to the conversation's transcript itself.
	/// This is what a request nobody is waiting on — a scroll-back top-up —
	/// wants.
	case transcript
	/// A presentation asked for the page and is told the outcome, whatever it
	/// turns out to be. The page is not prepended behind its back.
	case presentation
}
