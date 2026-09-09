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
}

/// Where the page a `CHATHISTORY BEFORE` brings back is delivered.
enum ServerHistoryDelivery {
	/// The client prepends the lines to the channel's transcript itself. This
	/// is what a request nobody is waiting on — a scroll-back top-up — wants.
	case transcript
	/// A presentation asked for the page and is told the outcome, whatever it
	/// turns out to be. The page is not prepended behind its back.
	case presentation
}

final class PendingServerHistoryRequest {
	let request: ServerHistoryRequest
	let label: String?
	let connectionIdentifier: String?
	/** Where the page goes, fixed when the request was made.

	 `presentation` is weak, so it cannot answer this later: a presentation that
	 went away between the request and the reply would silently turn a callback
	 request into a transcript one. */
	let delivery: ServerHistoryDelivery
	weak var channel: IRCChannel?
	weak var presentation: (any ServerHistoryPresentation)?
	var cancelled = false
	var timeoutTask: Task<Void, Never>?

	init(request: ServerHistoryRequest, label: String?, channel: IRCChannel, connectionIdentifier: String?,
	     presentation: (any ServerHistoryPresentation)?)
	{
		self.request = request
		self.label = label
		self.channel = channel
		self.connectionIdentifier = connectionIdentifier
		self.presentation = presentation
		delivery = presentation == nil ? .transcript : .presentation
	}

	isolated deinit { timeoutTask?.cancel() }
}

public extension IRCClient {
	func resetChatHistoryState() {
		chatHistoryFailedTargets.removeAll()
		let pending = serverHistoryRequests.values
		serverHistoryRequests.removeAll()
		for entry in pending {
			entry.timeoutTask?.cancel()
			entry.presentation?.receiveServerHistory(.cancelled, for: entry.request)
		}
		chatHistoryPrependChannel = nil
		chatHistoryPrependedLines = nil
		readMarkerSentDates.removeAll()
		readMarkerPendingChannels.removeAll()
		readMarkerTimer.stop()
	}

	func chatHistoryRequestLimit() -> UInt {
		IRCChatHistoryPolicy.requestLimit(serverMaximum: supportInfo.chatHistoryMaximumLines)
	}

	func chatHistoryIsAvailable(for channel: IRCChannel) -> Bool {
		let target = casefoldedTarget(channel.name)
		return IRCChatHistoryPolicy.canUseServerHistory(
			isLoggedIn: isLoggedIn,
			capabilityEnabled: environment.preferences.requestChatHistory
				&& isCapabilityEnabled(.chatHistory),
			isUtility: channel.isUtility,
			isDirectChat: channel.isDirectChat,
			isZNCQuery: channel.isPrivateMessage && channel.isPrivateMessageForZNCUser,
			targetFailed: chatHistoryFailedTargets.contains(target)
		)
	}

	func casefoldedTarget(_ target: String) -> String {
		supportInfo.casefoldString(target)
	}

	func chatHistoryTimestamp(for date: Date) -> String {
		"timestamp=\(sharedISOStandardDateFormatter().string(from: date))"
	}

	func chatHistoryLatestArguments(target: String, since date: Date?) -> [String] {
		ClientWireUtilities.chatHistoryArguments(
			subcommand: "LATEST",
			target: target,
			selector: date.map(chatHistoryTimestamp(for:)) ?? "*",
			limit: chatHistoryRequestLimit()
		)
	}

	func chatHistoryBeforeArguments(target: String, date: Date) -> [String] {
		ClientWireUtilities.chatHistoryArguments(
			subcommand: "BEFORE",
			target: target,
			selector: chatHistoryTimestamp(for: date),
			limit: chatHistoryRequestLimit()
		)
	}

	func newestKnownLineDate(for channel: IRCChannel) -> Date? {
		let viewDate = channel.lastLine?.receivedAt
		let storeDate = LogControllerHistoricLogFile.shared().newestLineDate(forView: channel.uniqueIdentifier)
		return [viewDate, storeDate].compactMap(\.self).max()
	}

	func noteChannelActivated(_ channel: IRCChannel) {
		guard !isTerminating else { return }
		requestChatHistory(for: channel)
		requestReadMarker(for: channel)
	}

	func requestChatHistory(for channel: IRCChannel) {
		guard chatHistoryIsAvailable(for: channel) else { return }
		send(
			ClientWireUtilities.chatHistoryCommand,
			arguments: chatHistoryLatestArguments(
				target: channel.name,
				since: newestKnownLineDate(for: channel)
			)
		)
	}

	func requestChatHistory(before date: Date, in channel: IRCChannel) {
		_ = requestServerHistory(ServerHistoryRequest(id: UUID(), before: date, oldestLineNumber: nil), in: channel)
	}

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

	func replayChatHistoryBatch(_ batchMessage: MessageBatch) {
		replayChatHistoryBatch(batchMessage, contents: batchMessage)
	}

	func noteChatHistoryFailure(_ message: Message) -> Bool {
		let label = message.messageTags?["label"] ?? message.parentBatchMessage?.labeledResponseBatch?.responseLabel
		if let label, label.hasPrefix(IRCChatHistoryPolicy.requestLabelPrefix) {
			guard let pending = serverHistoryRequests.values.first(where: { $0.label == label }) else { return false }
			finishServerHistory(pending, outcome: .failed(reason: message.params.last))
			return true
		}
		let target = message.params.dropFirst(2).dropLast().first(where: { findChannel($0) != nil })
		guard let target else { return true }
		if let channel = findChannel(target), let pending = serverHistoryRequests[channel.uniqueIdentifier] {
			if label == nil, pending.label == nil, message.params.dropFirst(2).first?.uppercased() == "BEFORE" {
				finishServerHistory(pending, outcome: .failed(reason: message.params.last))
			}
			return true
		}
		guard label == nil else { return true }
		let foldedTarget = casefoldedTarget(target)
		guard !chatHistoryFailedTargets.contains(foldedTarget) else { return false }
		chatHistoryFailedTargets.insert(foldedTarget)
		return true
	}

	func readMarkerIsAvailable(for channel: IRCChannel) -> Bool {
		IRCChatHistoryPolicy.canUseServerHistory(
			isLoggedIn: isLoggedIn,
			capabilityEnabled: environment.preferences.synchronizeReadMarkers
				&& isCapabilityEnabled(.readMarker),
			isUtility: channel.isUtility,
			isDirectChat: channel.isDirectChat,
			isZNCQuery: channel.isPrivateMessage && channel.isPrivateMessageForZNCUser,
			targetFailed: false
		)
	}

	func requestReadMarker(for channel: IRCChannel) {
		guard readMarkerIsAvailable(for: channel) else { return }
		send("MARKREAD", arguments: [channel.name])
	}

	func markChannel(asRead channel: IRCChannel) {
		let viewedDate = if let presentation = channel.presentation {
			presentation.lastRenderedLineDate()
		} else {
			newestKnownLineDate(for: channel)
		}
		guard let date = viewedDate else { return }
		scheduleReadMarker(for: channel, date: date)
	}

	func scheduleReadMarker(for channel: IRCChannel, date: Date) {
		guard readMarkerIsAvailable(for: channel),
		      IRCChatHistoryPolicy.shouldAdvanceMarker(
		      	candidate: date,
		      	previous: readMarkerSentDates[channel.uniqueIdentifier]
		      )
		else { return }
		let identifier = channel.uniqueIdentifier
		readMarkerPendingChannels[identifier] = max(date, readMarkerPendingChannels[identifier] ?? .distantPast)
		if !readMarkerTimer.isActive {
			readMarkerTimer.start(IRCChatHistoryPolicy.readMarkerDebounceInterval)
		}
	}

	func onReadMarkerTimer() {
		let channels = readMarkerPendingChannels
		readMarkerPendingChannels.removeAll()
		for (identifier, date) in channels {
			guard let channel = channelList.first(where: { $0.uniqueIdentifier == identifier }) else { continue }
			sendReadMarker(for: channel, date: date)
		}
	}

	func sendReadMarker(for channel: IRCChannel) {
		guard let date = newestKnownLineDate(for: channel) else { return }
		sendReadMarker(for: channel, date: date)
	}

	internal func sendReadMarker(for channel: IRCChannel, date newestDate: Date) {
		guard !isTerminating, readMarkerIsAvailable(for: channel),
		      IRCChatHistoryPolicy.shouldAdvanceMarker(
		      	candidate: newestDate,
		      	previous: readMarkerSentDates[channel.uniqueIdentifier]
		      )
		else { return }
		readMarkerSentDates[channel.uniqueIdentifier] = newestDate
		send("MARKREAD", arguments: [channel.name, chatHistoryTimestamp(for: newestDate)])
	}

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
		applyReadMarker(readMarkerSentDates[channel.uniqueIdentifier] ?? date, to: channel)
	}

	func applyReadMarker(_ date: Date, to channel: IRCChannel) {
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
		/* The lines past the marker may have arrived in a join burst, which is
		 printed without touching the unread count. The server has just said they
		 are unread, so the badge comes from here instead. setUnreadState leaves a
		 channel selected in the key window alone, and the count is set rather
		 than accumulated: the marker says "unread from here", not "one more". */
		if channel.isUnread == false {
			setUnreadState(for: channel)
		}
	}
}

extension IRCClient {
	@discardableResult
	func requestServerHistory(_ request: ServerHistoryRequest, in channel: IRCChannel,
	                          presentation: (any ServerHistoryPresentation)? = nil) -> Bool
	{
		guard serverHistoryRequestIsAdmissible(for: channel) else { return false }
		let requestLabel = IRCChatHistoryPolicy.requestLabelPrefix + request.id.uuidString
		let label = labeledResponseTrackingEnabled() ? requestLabel : nil
		let pending = PendingServerHistoryRequest(
			request: request, label: label, channel: channel, connectionIdentifier: socket?.uniqueIdentifier,
			presentation: presentation
		)
		serverHistoryRequests[channel.uniqueIdentifier] = pending
		pending.timeoutTask = Task { [weak self, weak pending] in
			try? await Task.sleep(for: .seconds(IRCChatHistoryPolicy.requestTimeout))
			guard !Task.isCancelled, let self, let pending else { return }
			timeoutServerHistory(pending)
		}
		sendCommand(
			ClientWireUtilities.chatHistoryCommand,
			arguments: chatHistoryBeforeArguments(target: channel.name, date: request.before),
			tags: label.map { ["label": $0] }
		)
		return true
	}

	/** Whether another `BEFORE` page can be asked for in this channel.

	 A request the client gave up on without a label stays retired for the rest
	 of the connection: an unlabelled reply cannot be told apart from the late
	 answer to the request that timed out, so a retry would be answered by
	 whichever arrived first. The transcript asks this before it offers a Retry
	 the client would silently drop. */
	func canRetryServerHistory(for channel: IRCChannel) -> Bool {
		serverHistoryRequestIsAdmissible(for: channel)
	}

	private func serverHistoryRequestIsAdmissible(for channel: IRCChannel) -> Bool {
		!isTerminating && chatHistoryIsAvailable(for: channel)
			&& serverHistoryRequests[channel.uniqueIdentifier] == nil
			&& serverHistoryRequests.count < IRCChatHistoryPolicy.maximumPendingRequests
	}

	func cancelServerHistoryRequest(_ request: ServerHistoryRequest) {
		guard let pending = serverHistoryRequests.values.first(where: { $0.request.id == request.id }) else { return }
		if pending.label != nil {
			finishServerHistory(pending, outcome: .cancelled)
		} else {
			// Without labels a late response cannot be distinguished from a retry.
			// Keep this slot retired until its batch/FAIL arrives or the connection resets.
			pending.cancelled = true
			pending.timeoutTask?.cancel()
			pending.presentation = nil
		}
	}

	func associateServerHistoryRequest(with batch: MessageBatch) {
		guard IRCBatchPolicy.isChatHistory(batch.batchType), let target = batch.batchParameters?.first,
		      let channel = findChannel(target), let pending = serverHistoryRequests[channel.uniqueIdentifier],
		      pending.connectionIdentifier == socket?.uniqueIdentifier,
		      pending.label == batch.labeledResponseBatch?.responseLabel else { return }
		batch.serverHistoryRequestID = pending.request.id
	}

	/** Whether the batch still answers the request that is waiting for it.

	 A page is only the answer while the connection, the channel and — for a
	 request the transcript is waiting on — the presentation are all the ones
	 the request was made against. Anything else is a reply to a request that
	 has been superseded, and printing it would put another channel's history
	 into this one. */
	private func batchStillAnswers(
		_ pending: PendingServerHistoryRequest,
		batch: MessageBatch
	) -> Bool {
		guard pending.cancelled == false,
		      let channel = pending.channel,
		      pending.connectionIdentifier == socket?.uniqueIdentifier,
		      findChannel(channel.name) === channel,
		      casefoldedTarget(batch.batchParameters?.first ?? "") == casefoldedTarget(channel.name)
		else {
			return false
		}

		guard pending.delivery == .presentation else { return true }

		return pending.presentation != nil && channel.presentation === pending.presentation
	}

	/** Whether a page arrived that nothing is waiting for.

	 Asked only once no pending request matches: the batch either names a
	 request that has since been retired, or carries a history label whose
	 request has. Either way its lines belong to a page the client gave up on
	 and are dropped rather than printed into whatever is on screen now. */
	private func batchOutlivedItsRequest(_ batch: MessageBatch) -> Bool {
		if batch.serverHistoryRequestID != nil {
			return true
		}

		let label = batch.labeledResponseBatch?.responseLabel

		return label?.hasPrefix(IRCChatHistoryPolicy.requestLabelPrefix) == true
	}

	func replayChatHistoryBatch(_ batch: MessageBatch, contents: MessageBatch) {
		let pending = serverHistoryRequests.values.first { $0.request.id == batch.serverHistoryRequestID }

		if let pending {
			guard batchStillAnswers(pending, batch: batch) else {
				finishServerHistory(pending, outcome: .cancelled)
				batchMessages.dequeueEntry(contents)
				return
			}

			chatHistoryPrependChannel = pending.channel
			chatHistoryPrependedLines = []
		} else if batchOutlivedItsRequest(batch) {
			batchMessages.dequeueEntry(contents)
			return
		}

		let channel = pending?.channel
		let incomplete = contents.deliveryState == .failed || batchMessages.queuedEntries.values.contains {
			$0.rootBatch === contents && $0.batchIsOpen
		}
		var pageMessageCount = 0
		for case let .message(message) in contents.queuedEntries {
			let inPage = batch === contents || batchMessage(ofType: "chathistory", containing: message) === batch
			if inPage {
				pageMessageCount += 1
				guard !chatHistoryMessageIsDuplicate(message) else { continue }
				message.markAsHistoric()
			}
			processIncomingMessage(message)
		}
		batchMessages.dequeueEntry(contents)
		guard let pending else { return }
		let lines = chatHistoryPrependedLines ?? []
		chatHistoryPrependChannel = nil
		chatHistoryPrependedLines = nil
		let outcome: ServerHistoryOutcome = incomplete ? .failed(reason: nil) : .page(
			lines: lines, extent: pending.label != nil && pageMessageCount == 0 ? .exhausted : .unknown
		)
		guard finishServerHistory(pending, outcome: outcome) else { return }
		if pending.delivery == .transcript, !incomplete {
			channel?.presentation?.prependHistoricLogLines(lines)
		}
	}

	private func timeoutServerHistory(_ pending: PendingServerHistoryRequest) {
		guard serverHistoryRequests.values.contains(where: { $0 === pending }) else { return }
		guard pending.channel != nil else {
			finishServerHistory(pending, outcome: .cancelled)
			return
		}
		if pending.label != nil {
			finishServerHistory(pending, outcome: .failed(reason: nil))
		} else {
			pending.presentation?.receiveServerHistory(.failed(reason: nil), for: pending.request)
			cancelServerHistoryRequest(pending.request)
		}
	}

	@discardableResult
	private func finishServerHistory(_ pending: PendingServerHistoryRequest, outcome: ServerHistoryOutcome) -> Bool {
		guard let key = serverHistoryRequests.first(where: { $0.value === pending })?.key else { return false }
		serverHistoryRequests.removeValue(forKey: key)
		pending.timeoutTask?.cancel()
		pending.timeoutTask = nil
		pending.presentation?.receiveServerHistory(outcome, for: pending.request)
		return true
	}
}
