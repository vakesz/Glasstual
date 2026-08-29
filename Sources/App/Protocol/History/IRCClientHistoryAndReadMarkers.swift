/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\\___/_/\_\\__|\\__,_|\\__,_|_|
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

enum IRCChatHistoryPolicy {
	static let defaultRequestLimit: UInt = 100
	static let readMarkerDebounceInterval: TimeInterval = 1

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
}

public extension IRCClient {
	@objc(resetChatHistoryState)
	func resetChatHistoryState() {
		chatHistoryFailedTargets.removeAll()
		chatHistoryPendingBeforeTargets.removeAll()
		chatHistoryPrependChannel = nil
		chatHistoryPrependedLines = nil
		readMarkerSentDates.removeAll()
		readMarkerPendingChannels.removeAll()
		readMarkerTimer.stop()
	}

	@objc(chatHistoryRequestLimit)
	func chatHistoryRequestLimit() -> UInt {
		IRCChatHistoryPolicy.requestLimit(serverMaximum: supportInfo.chatHistoryMaximumLines)
	}

	@objc(chatHistoryIsAvailableForChannel:)
	func chatHistoryIsAvailable(for channel: IRCChannel) -> Bool {
		let target = casefoldedTarget(channel.name)
		return IRCChatHistoryPolicy.canUseServerHistory(
			isLoggedIn: isLoggedIn,
			capabilityEnabled: isCapabilityEnabled(.chatHistory),
			isUtility: channel.isUtility,
			isDirectChat: channel.isDirectChat,
			isZNCQuery: channel.isPrivateMessage && channel.isPrivateMessageForZNCUser,
			targetFailed: chatHistoryFailedTargets.contains(target)
		)
	}

	@objc(casefoldedTarget:)
	func casefoldedTarget(_ target: String) -> String {
		supportInfo.casefoldString(target)
	}

	@objc(chatHistoryTimestampForDate:)
	func chatHistoryTimestamp(for date: Date) -> String {
		"timestamp=\(sharedISOStandardDateFormatter().string(from: date))"
	}

	@objc(chatHistoryLatestCommandForTarget:since:)
	func chatHistoryLatestCommand(target: String, since date: Date?) -> String {
		ClientWireUtilities.chatHistoryLatestCommand(
			target: target,
			selector: date.map(chatHistoryTimestamp(for:)) ?? "*",
			limit: chatHistoryRequestLimit()
		)
	}

	@objc(chatHistoryBeforeCommandForTarget:date:)
	func chatHistoryBeforeCommand(target: String, date: Date) -> String {
		ClientWireUtilities.chatHistoryBeforeCommand(
			target: target,
			selector: chatHistoryTimestamp(for: date),
			limit: chatHistoryRequestLimit()
		)
	}

	@objc(newestKnownLineDateForChannel:)
	func newestKnownLineDate(for channel: IRCChannel) -> Date? {
		let viewDate = channel.lastLine?.receivedAt
		let storeDate = LogControllerHistoricLogFile.shared().newestLineDate(forView: channel.uniqueIdentifier)
		return [viewDate, storeDate].compactMap(\.self).max()
	}

	@objc(noteChannelActivated:)
	func noteChannelActivated(_ channel: IRCChannel) {
		guard !isTerminating else { return }
		requestChatHistory(for: channel)
		requestReadMarker(for: channel)
	}

	@objc(requestChatHistoryForChannel:)
	func requestChatHistory(for channel: IRCChannel) {
		guard chatHistoryIsAvailable(for: channel) else { return }
		sendLine(chatHistoryLatestCommand(target: channel.name, since: newestKnownLineDate(for: channel)))
	}

	@objc(requestChatHistoryBeforeDate:inChannel:)
	func requestChatHistory(before date: Date, in channel: IRCChannel) {
		guard chatHistoryIsAvailable(for: channel) else { return }
		let target = casefoldedTarget(channel.name)
		guard !chatHistoryPendingBeforeTargets.contains(target) else { return }
		chatHistoryPendingBeforeTargets.insert(target)
		sendLine(chatHistoryBeforeCommand(target: channel.name, date: date))
	}

	@objc(chatHistoryMessageIsDuplicate:)
	func chatHistoryMessageIsDuplicate(_ message: Message) -> Bool {
		guard let channel = channel(forTargetedMessage: message) else { return false }
		let historicLog = LogControllerHistoricLogFile.shared()
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

	@objc(replayChatHistoryBatch:)
	func replayChatHistoryBatch(_ batchMessage: MessageBatch) {
		let target = batchMessage.batchParameters?.first
		let channel = target.flatMap(findChannel(_:))
		let foldedTarget = target.map(casefoldedTarget(_:))
		let prepend = channel != nil && foldedTarget.map(chatHistoryPendingBeforeTargets.contains) == true

		if prepend, let channel, let foldedTarget {
			chatHistoryPendingBeforeTargets.remove(foldedTarget)
			chatHistoryPrependChannel = channel
			chatHistoryPrependedLines = []
		}
		for case let .message(message) in batchMessage.queuedEntries
			where !chatHistoryMessageIsDuplicate(message)
		{
			message.markAsHistoric()
			processIncomingMessage(message)
		}
		batchMessages.dequeueEntry(batchMessage)
		if prepend {
			flushChatHistoryPrependedLines()
		}
	}

	@objc(flushChatHistoryPrependedLines)
	func flushChatHistoryPrependedLines() {
		let channel = chatHistoryPrependChannel
		let lines = chatHistoryPrependedLines ?? []
		chatHistoryPrependChannel = nil
		chatHistoryPrependedLines = nil
		guard let channel, !lines.isEmpty else { return }
		channel.presentation?.prependHistoricLogLines(lines)
	}

	@objc(noteChatHistoryFailure:)
	func noteChatHistoryFailure(_ message: Message) -> Bool {
		let target = message.params.dropFirst(2).dropLast().first(where: { findChannel($0) != nil })
		guard let target else { return true }
		let foldedTarget = casefoldedTarget(target)
		chatHistoryPendingBeforeTargets.remove(foldedTarget)
		guard !chatHistoryFailedTargets.contains(foldedTarget) else { return false }
		chatHistoryFailedTargets.insert(foldedTarget)
		return true
	}

	@objc(readMarkerIsAvailableForChannel:)
	func readMarkerIsAvailable(for channel: IRCChannel) -> Bool {
		IRCChatHistoryPolicy.canUseServerHistory(
			isLoggedIn: isLoggedIn,
			capabilityEnabled: isCapabilityEnabled(.readMarker),
			isUtility: channel.isUtility,
			isDirectChat: channel.isDirectChat,
			isZNCQuery: channel.isPrivateMessage && channel.isPrivateMessageForZNCUser,
			targetFailed: false
		)
	}

	@objc(requestReadMarkerForChannel:)
	func requestReadMarker(for channel: IRCChannel) {
		guard readMarkerIsAvailable(for: channel) else { return }
		send("MARKREAD", arguments: [channel.name])
	}

	@objc(markChannelAsRead:)
	func markChannel(asRead channel: IRCChannel) {
		guard let date = newestKnownLineDate(for: channel) else { return }
		scheduleReadMarker(for: channel, date: date)
	}

	@objc(scheduleReadMarkerForChannel:date:)
	func scheduleReadMarker(for channel: IRCChannel, date: Date) {
		guard readMarkerIsAvailable(for: channel),
		      IRCChatHistoryPolicy.shouldAdvanceMarker(
		      	candidate: date,
		      	previous: readMarkerSentDates[channel.uniqueIdentifier]
		      )
		else { return }
		readMarkerPendingChannels.append(channel)
		if !readMarkerTimer.isActive {
			readMarkerTimer.start(IRCChatHistoryPolicy.readMarkerDebounceInterval)
		}
	}

	@objc(onReadMarkerTimer)
	func onReadMarkerTimer() {
		let channels = readMarkerPendingChannels
		readMarkerPendingChannels.removeAll()
		for channel in channels {
			sendReadMarker(for: channel)
		}
	}

	@objc(sendReadMarkerForChannel:)
	func sendReadMarker(for channel: IRCChannel) {
		guard readMarkerIsAvailable(for: channel), let newestDate = newestKnownLineDate(for: channel),
		      IRCChatHistoryPolicy.shouldAdvanceMarker(
		      	candidate: newestDate,
		      	previous: readMarkerSentDates[channel.uniqueIdentifier]
		      )
		else { return }
		readMarkerSentDates[channel.uniqueIdentifier] = newestDate
		send("MARKREAD", arguments: [channel.name, chatHistoryTimestamp(for: newestDate)])
	}

	@objc(receiveReadMarker:)
	func receiveReadMarker(_ message: Message) {
		guard message.params.count >= 2, let channel = findChannel(message.params[0]),
		      message.params[1].hasPrefix("timestamp="),
		      let date = sharedISOStandardDateFormatter().date(from: String(message.params[1].dropFirst(10)))
		else { return }
		if IRCChatHistoryPolicy.shouldAdvanceMarker(
			candidate: date,
			previous: readMarkerSentDates[channel.uniqueIdentifier]
		) {
			readMarkerSentDates[channel.uniqueIdentifier] = date
		}
		applyReadMarker(date, to: channel)
	}

	@objc(applyReadMarkerDate:toChannel:)
	func applyReadMarker(_ date: Date, to channel: IRCChannel) {
		applyReadMarkerOnMainActor(date, to: channel)
	}
}

private extension IRCClient {
	@MainActor
	func applyReadMarkerOnMainActor(_ date: Date, to channel: IRCChannel) {
		let newestDate = newestKnownLineDate(for: channel)
		if newestDate.map({ $0 > date }) != true {
			if channel.isUnread || channel.nicknameHighlightCount > 0 {
				channel.resetState()
				output?.refreshMessageCount(for: channel)
				DockIcon.updateDockIcon()
			}
			return
		}

		guard let output,
		      !output.isItemVisible(channel) || !output.windowIsKey
		else { return }
		channel.presentation?.mark(at: date)
	}
}
