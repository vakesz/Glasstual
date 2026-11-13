// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

enum ChatHistoryPolicy {
	static let defaultRequestLimit: UInt = 100
	static let readMarkerDebounceInterval: TimeInterval = 1
	static let maximumPendingRequests = 64
	static let requestTimeout: TimeInterval = 30
	static let requestLabelPrefix = "history-"

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
}

extension ServerSession {
	func resetChatHistoryState() {
		chatHistory.failedTargets.removeAll()
		let pending = chatHistory.serverRequests.values
		chatHistory.serverRequests.removeAll()
		chatHistory.requestsByBatchToken.removeAll()
		for entry in pending {
			entry.timeoutTimer?.stop()
			entry.presentation?.receiveServerHistory(.cancelled, for: entry.request)
		}
		chatHistory.prependConversation = nil
		chatHistory.prependedLines = nil
		chatHistory.refusesMessageIdentifiers = false
		resetChatHistoryPaging()
		resetChatHistoryTargets()
		readMarkers.sentDates.removeAll()
		readMarkers.pendingConversations.removeAll()
		readMarkers.timer.stop()
	}

	func chatHistoryRequestLimit() -> UInt {
		ChatHistoryLimit.clamp(ChatHistoryPolicy.defaultRequestLimit, serverMaximum: supportInfo.chatHistoryMaximumLines)
	}

	/// The references the server takes: `MSGREFTYPES`, less message
	/// identifiers once it has refused one on this connection.
	var chatHistoryReferenceSupport: ChatHistoryReferenceSupport {
		ChatHistoryReferenceSupport(
			timestamps: supportInfo.chatHistorySupportsTimestamps,
			messageIdentifiers: supportInfo.chatHistorySupportsMessageIdentifiers && chatHistory.refusesMessageIdentifiers == false
		)
	}

	/// The parameters of `command` as this server takes them, or `nil` when it
	/// cannot be asked here.
	func chatHistoryArguments(_ command: ChatHistoryCommand) -> [String]? {
		try? command.arguments(support: chatHistoryReferenceSupport)
	}

	func chatHistoryIsAvailable(for conversation: Conversation) -> Bool {
		let target = supportInfo.casefoldString(conversation.name)
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

	func chatHistoryTimestamp(for date: Date) -> String {
		"timestamp=\(DateFormatting.iso8601String(from: date))"
	}

	/// The request goes out as arguments rather than an assembled line: the
	/// outbound transport is what builds the line and attaches the message tags
	/// a labelled request needs.
	func chatHistoryLatestArguments(target: String, since date: Date?) -> [String]? {
		let reference: ChatHistoryReference = if chatHistoryReferenceSupport.timestamps, let date {
			.timestamp(date)
		} else {
			.unbounded
		}
		return chatHistoryArguments(.latest(target: target, after: reference, limit: chatHistoryRequestLimit()))
	}

	/// A scroll-back page: before the oldest line's message identifier where
	/// the server takes those, and before its time otherwise.
	func chatHistoryBeforeArguments(target: String, request: ServerHistoryRequest) -> [String]? {
		let reference = ChatHistoryReference.preferred(
			messageIdentifier: request.messageIdentifier,
			timestamp: request.before,
			support: chatHistoryReferenceSupport
		)
		return reference.flatMap { chatHistoryArguments(.before(target: target, $0, limit: chatHistoryRequestLimit())) }
	}

	func newestKnownServerTimestamp(for conversation: Conversation) -> Date? {
		let viewDate = conversation.lastLine?.serverTimestamp
		let storeDate = Scrollback.shared.duplicates.newestReadMarkerTimestamp(forView: conversation.uniqueIdentifier)
		return [viewDate, storeDate].compactMap(\.self).max()
	}

	/** The newest line a person wrote in `conversation`, on screen or in storage.

	 A read marker is answered against this rather than the most recent local event:
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
		requestChatHistoryCatchUp(for: conversation)
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
		if noteChatHistoryTargetsFailure(message, label: label) {
			return true
		}
		if label?.hasPrefix(ChatHistoryPolicy.targetsLabelPrefix) == true {
			return false
		}
		if let paging = pagingFailed(
			label: label?.hasPrefix(ChatHistoryPolicy.pagingLabelPrefix) == true ? label : nil,
			target: label == nil ? message.params.dropFirst(2).dropLast().first(where: { findConversation($0) != nil }) : nil
		) {
			endPaging(paging, failure: message.params.last)
			return true
		}
		if let label, label.hasPrefix(ChatHistoryPolicy.pagingLabelPrefix) {
			return false
		}
		if let label, label.hasPrefix(ChatHistoryPolicy.requestLabelPrefix) {
			guard let pending = chatHistory.serverRequests.values.first(where: { $0.label == label }) else { return false }
			if retryWithTimestamp(pending, after: message) {
				return true
			}
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
		if message.param(at: 1) == "INVALID_MSGREFTYPE" {
			chatHistory.refusesMessageIdentifiers = true
			return true
		}
		let foldedTarget = supportInfo.casefoldString(target)
		guard !chatHistory.failedTargets.contains(foldedTarget) else { return false }
		chatHistory.failedTargets.insert(foldedTarget)
		return true
	}

	/** `INVALID_MSGREFTYPE` for a page asked for by message identifier: the
	 server does not take them after all, whatever `MSGREFTYPES` said. The same
	 page is asked for once more by time, and message identifiers are not used
	 again on this connection. */
	private func retryWithTimestamp(_ pending: PendingServerHistoryRequest, after message: Message) -> Bool {
		guard message.param(at: 1) == "INVALID_MSGREFTYPE",
		      chatHistory.refusesMessageIdentifiers == false,
		      pending.request.messageIdentifier != nil,
		      let conversation = pending.conversation,
		      let key = chatHistory.serverRequests.first(where: { $0.value === pending })?.key
		else { return false }
		chatHistory.refusesMessageIdentifiers = true
		chatHistory.serverRequests.removeValue(forKey: key)
		pending.timeoutTimer?.stop()
		pending.timeoutTimer = nil
		let retried = requestServerHistory(pending.request, in: conversation, presentation: pending.presentation)
		if retried == false {
			pending.presentation?.receiveServerHistory(.failed(reason: message.params.last), for: pending.request)
		}
		return true
	}
}
