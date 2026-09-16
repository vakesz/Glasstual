/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 *
 *  * Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 *  * Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 *  * Neither the name of Textual, "Codeux Software, LLC", nor the
 *    names of its contributors may be used to endorse or promote products
 *    derived from this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED. IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
 * FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
 * OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
 * LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
 * OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
 * SUCH DAMAGE.
 *
 *********************************************************************** */

import Foundation

/** The chat history this session has asked for and is still waiting on.

 A `CHATHISTORY` reply arrives as a batch some time after the request, so what
 the client is waiting for outlives the call that asked: which channel the page
 belongs to, the lines collected so far, the targets the server refused, and
 the `BEFORE` requests still outstanding. */
struct ChatHistorySession {
	/// The channel whose page is being collected, `nil` between batches.
	var prependChannel: Channel?
	/// The lines of the page collected so far.
	var prependedLines: [LogLine]?
	/// Casefolded targets whose history request the server refused.
	var failedTargets: Set<String> = []
	/// `BEFORE` requests keyed by channel identity, independent of CASEMAPPING.
	var serverRequests: [String: PendingServerHistoryRequest] = [:]
}

/// The one command name every chat-history request goes out under.
let chatHistoryCommand = "CHATHISTORY"

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
		isUtility: Bool,
		isDirectChat: Bool,
		isZNCQuery: Bool,
		targetFailed: Bool
	) -> Bool {
		isLoggedIn && capabilityEnabled && !isUtility && !isDirectChat && !isZNCQuery && !targetFailed
	}

	static func shouldAdvanceMarker(candidate: Date, previous: Date?) -> Bool {
		previous == nil || candidate > previous ?? .distantFuture
	}

	/** Whether a read marker may be placed at `line`'s time.

	 A marker is a server timestamp, and it is compared with the server time of
	 every line that arrives after it. Only a line the server delivered — a
	 conversation line carrying its `msgid` — is stamped on that clock; the
	 client's own events and a message it printed before any echo are stamped by
	 the local one. A marker taken from those sat wherever the local clock was,
	 and a clock running ahead silenced the lines the server sent until it
	 caught up. */
	static func marksReadPosition(lineType: LogLineType, messageIdentifier: String?) -> Bool {
		lineType.isConversation && messageIdentifier != nil
	}
}

@MainActor
extension Client {
	func resetChatHistoryState() {
		chatHistory.failedTargets.removeAll()
		let pending = chatHistory.serverRequests.values
		chatHistory.serverRequests.removeAll()
		for entry in pending {
			entry.timeoutTask?.cancel()
			entry.presentation?.receiveServerHistory(.cancelled, for: entry.request)
		}
		chatHistory.prependChannel = nil
		chatHistory.prependedLines = nil
		readMarkers.sentDates.removeAll()
		readMarkers.pendingChannels.removeAll()
		readMarkers.timer.stop()
	}

	func chatHistoryRequestLimit() -> UInt {
		ChatHistoryPolicy.requestLimit(serverMaximum: supportInfo.chatHistoryMaximumLines)
	}

	func chatHistoryIsAvailable(for channel: Channel) -> Bool {
		let target = casefoldedTarget(channel.name)
		return ChatHistoryPolicy.canUseServerHistory(
			isLoggedIn: isLoggedIn,
			capabilityEnabled: environment.preferences.requestChatHistory
				&& isCapabilityEnabled(.chatHistory),
			isUtility: channel.isUtility,
			isDirectChat: channel.isDirectChat,
			isZNCQuery: channel.isPrivateMessage && channel.isPrivateMessageForZNCUser,
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

	func newestKnownLineDate(for channel: Channel) -> Date? {
		let viewDate = channel.lastLine?.receivedAt
		let storeDate = Scrollback.shared.newestLineDate(forView: channel.uniqueIdentifier)
		return [viewDate, storeDate].compactMap(\.self).max()
	}

	/** The newest line a person wrote in `channel`, on screen or in storage.

	 A read marker is answered against this rather than ``newestKnownLineDate``:
	 joining prints a join line, a topic and a mode stamped now, and a marker
	 older than that burst does not mean anything in it went unread. */
	func newestKnownConversationLineDate(for channel: Channel) -> Date? {
		let viewDate = channel.presentation?.newestConversationLineDate()
		let storeDate = Scrollback.shared
			.newestConversationLineDate(forView: channel.uniqueIdentifier)
		return [viewDate, storeDate].compactMap(\.self).max()
	}

	func noteChannelActivated(_ channel: Channel) {
		guard !isTerminating else { return }
		requestChatHistory(for: channel)
		requestReadMarker(for: channel)
	}

	func requestChatHistory(for channel: Channel) {
		guard chatHistoryIsAvailable(for: channel) else { return }
		send(
			chatHistoryCommand,
			arguments: chatHistoryLatestArguments(
				target: channel.name,
				since: newestKnownLineDate(for: channel)
			)
		)
	}

	func requestChatHistory(before date: Date, in channel: Channel) {
		_ = requestServerHistory(ServerHistoryRequest(id: UUID(), before: date, oldestLineNumber: nil), in: channel)
	}

	func chatHistoryMessageIsDuplicate(_ message: Message) -> Bool {
		guard let channel = channel(forTargetedMessage: message) else { return false }
		let historicLog = Scrollback.shared
		if let identifier = message.messageIdentifier, !identifier.isEmpty {
			return historicLog.containsMessageIdentifier(identifier, forView: channel.uniqueIdentifier)
		}
		guard message.isHistoric, let text = message.params.last else { return false }
		return historicLog.containsLine(
			receivedAt: message.receivedAt,
			nickname: message.senderNickname,
			messageBody: text,
			forView: channel.uniqueIdentifier
		)
	}

	func replayChatHistoryBatch(_ batchMessage: MessageBatch) {
		replayChatHistoryBatch(batchMessage, contents: batchMessage)
	}

	func noteChatHistoryFailure(_ message: Message) -> Bool {
		let label = message.messageTags?["label"] ?? message.parentBatchMessage?.labeledResponseBatch?.responseLabel
		if let label, label.hasPrefix(ChatHistoryPolicy.requestLabelPrefix) {
			guard let pending = chatHistory.serverRequests.values.first(where: { $0.label == label }) else { return false }
			finishServerHistory(pending, outcome: .failed(reason: message.params.last))
			return true
		}
		let target = message.params.dropFirst(2).dropLast().first(where: { findChannel($0) != nil })
		guard let target else { return true }
		if let channel = findChannel(target), let pending = chatHistory.serverRequests[channel.uniqueIdentifier] {
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
