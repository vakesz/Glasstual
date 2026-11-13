// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/** The chat history this session has asked for and is still waiting on.

 A `CHATHISTORY` reply arrives as a batch some time after the request, so what
 the session is waiting for outlives the call that asked: which conversation
 the page belongs to, the lines collected so far, the targets the server
 refused, and the `BEFORE` requests still outstanding. */
struct ChatHistorySession {
	/// The conversation whose page is being collected, `nil` between batches.
	var prependConversation: Conversation?
	/// The lines of the page collected so far.
	var prependedLines: [ChatLine]?
	/// Casefolded targets whose history request the server refused.
	var failedTargets: Set<String> = []
	/// `BEFORE` requests keyed by conversation identity, independent of
	/// CASEMAPPING.
	var serverRequests: [String: PendingServerHistoryRequest] = [:]
	/// Which request a `CHATHISTORY` batch answers, keyed by the batch's token.
	/// A batch is the wire's record of a group of lines; what this session asked
	/// for is this subsystem's own bookkeeping and stays here.
	var requestsByBatchToken: [String: UUID] = [:]
	/// Set once the server answered a message identifier with
	/// `INVALID_MSGREFTYPE`: pages are asked for by time from then on.
	var refusesMessageIdentifiers = false
	/// Catch-up and gap-fill paging in flight, keyed by conversation identity.
	/// One per conversation, and none while a scroll-back page is pending.
	var paging: [String: PendingChatHistoryPaging] = [:]
	/// Messages known to be missing, keyed by conversation identity.
	var gaps: [String: ChatHistoryGap] = [:]
	/// The `TARGETS` request in flight; one at a time.
	var targetsSweep: PendingTargetsSweep?
	/// Delays the automatic sweep after registration, so the catch-ups the
	/// autojoin starts go first.
	var targetsSweepTimer: SessionTimer?
	/// Set once the server refused `TARGETS`; it is not asked again on this connection.
	var refusesTargets = false
}
