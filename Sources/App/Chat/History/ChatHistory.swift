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
}

enum ChatHistoryPolicy {
	static let defaultRequestLimit: UInt = 100
	static let readMarkerDebounceInterval: TimeInterval = 1
	static let maximumPendingRequests = 64
	static let requestTimeout: TimeInterval = 30
	static let requestLabelPrefix = "history-"

	static func requestLimit(serverMaximum: UInt) -> UInt {
		guard serverMaximum > 0, serverMaximum <= defaultRequestLimit else { return defaultRequestLimit }
		return serverMaximum
	}

	static func canUseServerHistory(
		isLoggedIn: Bool,
		capabilityEnabled: Bool,
		isConsole: Bool,
		isDirectChat: Bool,
		isZNCDirectConversation: Bool,
		targetFailed: Bool
	) -> Bool {
		isLoggedIn && capabilityEnabled && !isConsole && !isDirectChat && !isZNCDirectConversation && !targetFailed
	}

	static func shouldAdvanceMarker(candidate: Date, previous: Date?) -> Bool {
		previous == nil || candidate > previous ?? .distantFuture
	}

	/** Whether a read marker may be placed at `line`'s time.

	 A marker is a server timestamp, and it is compared with the server time of
	 every line that arrives after it. Only a line the server delivered — a
	 conversation line carrying its `msgid` — is stamped on that clock; the
	 session's own events and a message it printed before any echo are stamped by
	 the local one. A marker taken from those sat wherever the local clock was,
	 and a clock running ahead silenced the lines the server sent until it
	 caught up. */
	static func marksReadPosition(lineType: ChatLineKind, messageIdentifier: String?) -> Bool {
		lineType.isConversation && messageIdentifier != nil
	}
}

@MainActor
extension ServerSession {
	func resetChatHistoryState() {
		chatHistory.failedTargets.removeAll()
		let pending = chatHistory.serverRequests.values
		chatHistory.serverRequests.removeAll()
		chatHistory.requestsByBatchToken.removeAll()
		for entry in pending {
			entry.timeoutTask?.cancel()
			entry.presentation?.receiveServerHistory(.cancelled, for: entry.request)
		}
		chatHistory.prependConversation = nil
		chatHistory.prependedLines = nil
		readMarkers.sentDates.removeAll()
		readMarkers.pendingConversations.removeAll()
		readMarkers.timer.stop()
	}

	func chatHistoryRequestLimit() -> UInt {
		ChatHistoryPolicy.requestLimit(serverMaximum: supportInfo.chatHistoryMaximumLines)
	}

	func chatHistoryIsAvailable(for conversation: Conversation) -> Bool {
		let target = casefoldedTarget(conversation.name)
		return ChatHistoryPolicy.canUseServerHistory(
			isLoggedIn: isLoggedIn,
			capabilityEnabled: environment.settings.requestChatHistory
				&& isCapabilityEnabled(.chatHistory),
			isConsole: conversation.isConsole,
			isDirectChat: conversation.isDirectChat,
			isZNCDirectConversation: conversation.isDirect && conversation.isDirectForZNCUser,
			targetFailed: chatHistory.failedTargets.contains(target)
		)
	}

	func casefoldedTarget(_ target: String) -> String {
		supportInfo.casefoldString(target)
	}

	func chatHistoryTimestamp(for date: Date) -> String {
		"timestamp=\(DateFormatting.iso8601String(from: date))"
	}

	/// The request goes out as arguments rather than an assembled line: the
	/// outbound transport is what builds the line and attaches the message tags
	/// a labelled request needs.
	func chatHistoryLatestArguments(target: String, since date: Date?) -> [String] {
		["LATEST", target, date.map(chatHistoryTimestamp(for:)) ?? "*", String(chatHistoryRequestLimit())]
	}

	func chatHistoryBeforeArguments(target: String, date: Date) -> [String] {
		["BEFORE", target, chatHistoryTimestamp(for: date), String(chatHistoryRequestLimit())]
	}

	func newestKnownLineDate(for conversation: Conversation) -> Date? {
		let viewDate = conversation.lastLine?.receivedAt
		let storeDate = Scrollback.shared.duplicates.newestLineDate(forView: conversation.uniqueIdentifier)
		return [viewDate, storeDate].compactMap(\.self).max()
	}

	/** The newest line a person wrote in `conversation`, on screen or in storage.

	 A read marker is answered against this rather than ``newestKnownLineDate``:
	 joining prints a join line, a topic and a mode stamped now, and a marker
	 older than that burst does not mean anything in it went unread. */
	func newestKnownConversationLineDate(for conversation: Conversation) -> Date? {
		let viewDate = conversation.presentation?.newestConversationLineDate()
		let storeDate = Scrollback.shared.duplicates
			.newestConversationLineDate(forView: conversation.uniqueIdentifier)
		return [viewDate, storeDate].compactMap(\.self).max()
	}

	func noteConversationActivated(_ conversation: Conversation) {
		guard !isTerminating else { return }
		requestChatHistory(for: conversation)
		requestReadMarker(for: conversation)
	}

	func requestChatHistory(for conversation: Conversation) {
		guard chatHistoryIsAvailable(for: conversation) else { return }
		send(
			.chathistory,
			arguments: chatHistoryLatestArguments(
				target: conversation.name,
				since: newestKnownLineDate(for: conversation)
			)
		)
	}

	func requestChatHistory(before date: Date, in conversation: Conversation) {
		_ = requestServerHistory(ServerHistoryRequest(id: UUID(), before: date, oldestLineNumber: nil), in: conversation)
	}

	func chatHistoryMessageIsDuplicate(_ message: Message) -> Bool {
		guard let conversation = conversation(forTargetedMessage: message) else { return false }
		let duplicates = Scrollback.shared.duplicates
		if let identifier = message.messageIdentifier, !identifier.isEmpty {
			return duplicates.containsMessageIdentifier(identifier, forView: conversation.uniqueIdentifier)
		}
		guard message.isReplayed, let text = message.params.last else { return false }
		return duplicates.containsLine(
			receivedAt: message.receivedAt,
			nickname: message.senderNickname,
			messageBody: text,
			forView: conversation.uniqueIdentifier
		)
	}

	func replayChatHistoryBatch(_ batchMessage: MessageBatch) {
		replayChatHistoryBatch(batchMessage, contents: batchMessage)
	}

	func noteChatHistoryFailure(_ message: Message) -> Bool {
		let label = message.messageTags?["label"] ?? message.parentBatchMessage?.labeledResponseBatch?.labeledDelivery.label
		if let label, label.hasPrefix(ChatHistoryPolicy.requestLabelPrefix) {
			guard let pending = chatHistory.serverRequests.values.first(where: { $0.label == label }) else { return false }
			finishServerHistory(pending, outcome: .failed(reason: message.params.last))
			return true
		}
		let target = message.params.dropFirst(2).dropLast().first(where: { findConversation($0) != nil })
		guard let target else { return true }
		if let conversation = findConversation(target), let pending = chatHistory.serverRequests[conversation.uniqueIdentifier] {
			if label == nil, pending.label == nil, message.params.dropFirst(2).first?.uppercased() == "BEFORE" {
				finishServerHistory(pending, outcome: .failed(reason: message.params.last))
			}
			return true
		}
		guard label == nil else { return true }
		let foldedTarget = casefoldedTarget(target)
		guard !chatHistory.failedTargets.contains(foldedTarget) else { return false }
		chatHistory.failedTargets.insert(foldedTarget)
		return true
	}
}
