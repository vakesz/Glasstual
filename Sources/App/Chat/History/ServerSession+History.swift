// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

extension ServerSession {
	@discardableResult
	func requestServerHistory(_ request: ServerHistoryRequest, in conversation: Conversation,
	                          presentation: (any ServerHistoryPresenting)? = nil) -> Bool
	{
		guard serverHistoryRequestIsAdmissible(for: conversation),
		      let arguments = chatHistoryBeforeArguments(target: conversation.name, request: request) else { return false }
		let requestLabel = ChatHistoryPolicy.requestLabelPrefix + request.id.uuidString
		let label = labeledResponseTrackingEnabled() ? requestLabel : nil
		let pending = PendingServerHistoryRequest(
			request: request, label: label, conversation: conversation, connectionIdentifier: socket?.uniqueIdentifier,
			presentation: presentation
		)
		chatHistory.serverRequests[conversation.uniqueIdentifier] = pending
		pending.timeoutTimer = SessionTimer.once(after: ChatHistoryPolicy.requestTimeout) { [weak self, weak pending] in
			guard let self, let pending else { return }
			timeoutServerHistory(pending)
		}
		sendCommand(
			.chathistory,
			arguments: arguments,
			tags: label.map { ["label": $0] }
		)
		return true
	}

	/** Whether another `BEFORE` page can be asked for in this conversation.

	 A request the session gave up on without a label stays retired for the rest
	 of the connection: an unlabelled reply cannot be told apart from the late
	 answer to the request that timed out, so a retry would be answered by
	 whichever arrived first. The transcript asks this before it offers a Retry
	 the session would silently drop. */
	func canRetryServerHistory(for conversation: Conversation, request: ServerHistoryRequest? = nil) -> Bool {
		serverHistoryRequestIsAdmissible(for: conversation) && (request.map {
			chatHistoryBeforeArguments(target: conversation.name, request: $0) != nil
		} ?? supportInfo.chatHistorySupportsTimestamps)
	}

	private func serverHistoryRequestIsAdmissible(for conversation: Conversation) -> Bool {
		!isTerminating && chatHistoryIsAvailable(for: conversation)
			&& chatHistory.serverRequests[conversation.uniqueIdentifier] == nil
			&& chatHistory.paging[conversation.uniqueIdentifier] == nil
			&& chatHistory.serverRequests.count < ChatHistoryPolicy.maximumPendingRequests
	}

	func cancelServerHistoryRequest(_ request: ServerHistoryRequest) {
		guard let pending = chatHistory.serverRequests.values.first(where: { $0.request.id == request.id }) else { return }
		if pending.label != nil {
			finishServerHistory(pending, outcome: .cancelled)
		} else {
			// Without labels a late response cannot be distinguished from a retry.
			// Keep this slot retired until its batch/FAIL arrives or the connection resets.
			pending.cancelled = true
			pending.timeoutTimer?.stop()
			pending.presentation = nil
		}
	}

	func associateServerHistoryRequest(with batch: MessageBatch) {
		guard batch.kind == .chatHistory, let target = batch.batchParameters?.first,
		      let conversation = findConversation(target), let pending = chatHistory.serverRequests[conversation.uniqueIdentifier],
		      pending.connectionIdentifier == socket?.uniqueIdentifier,
		      pending.label == batch.labeledResponseBatch?.labeledDelivery.label else { return }
		/* A batch that is never closed would leave its note behind, so the table
		 is trimmed to the batches the connection still has open before the new
		 one is written. `batch` is open here, so it survives the trim. */
		chatHistory.requestsByBatchToken = chatHistory.requestsByBatchToken.filter {
			batchMessages.queuedEntry(withBatchToken: $0.key) != nil
		}
		chatHistory.requestsByBatchToken[batch.batchToken] = pending.request.id
	}

	/// The request `batch` was recorded as answering, if it answers one.
	private func serverHistoryRequestID(for batch: MessageBatch) -> UUID? {
		chatHistory.requestsByBatchToken[batch.batchToken]
	}

	/** Whether the batch still answers the request that is waiting for it.

	 A page is only the answer while the connection, the conversation and — for a
	 request the transcript is waiting on — the presentation are all the ones the
	 request was made against. Anything else is a reply to a request that has
	 been superseded, and printing it would put another conversation's history
	 into this one. */
	private func batchStillAnswers(
		_ pending: PendingServerHistoryRequest,
		batch: MessageBatch
	) -> Bool {
		guard pending.cancelled == false,
		      let conversation = pending.conversation,
		      pending.connectionIdentifier == socket?.uniqueIdentifier,
		      findConversation(conversation.name) === conversation,
		      supportInfo.casefoldString(batch.batchParameters?.first ?? "") == supportInfo.casefoldString(conversation.name)
		else {
			return false
		}

		guard pending.delivery == .presentation else { return true }

		return pending.presentation != nil && conversation.presentation === pending.presentation
	}

	/** Whether a page arrived that nothing is waiting for.

	 Asked only once no pending request matches: the batch either names a
	 request that has since been retired, or carries a history label whose
	 request has. Either way its lines belong to a page the session gave up on
	 and are dropped rather than printed into whatever is on screen now. */
	private func batchOutlivedItsRequest(_ batch: MessageBatch, requestID: UUID?) -> Bool {
		if requestID != nil {
			return true
		}

		let label = batch.labeledResponseBatch?.labeledDelivery.label

		return label?.hasPrefix(ChatHistoryPolicy.requestLabelPrefix) == true
	}

	func replayChatHistoryBatch(_ batch: MessageBatch, contents: MessageBatch) {
		if serverHistoryRequestID(for: batch) == nil, let paging = pagingAnswered(by: batch) {
			replayPagingBatch(batch, contents: contents, paging: paging)
			return
		}
		let requestID = serverHistoryRequestID(for: batch)
		chatHistory.requestsByBatchToken.removeValue(forKey: batch.batchToken)
		let pending = chatHistory.serverRequests.values.first { $0.request.id == requestID }

		if let pending {
			guard batchStillAnswers(pending, batch: batch) else {
				finishServerHistory(pending, outcome: .cancelled)
				batchMessages.dequeueEntry(contents)
				return
			}

			chatHistory.prependConversation = pending.conversation
			chatHistory.prependedLines = []
		} else if batchOutlivedItsRequest(batch, requestID: requestID) {
			batchMessages.dequeueEntry(contents)
			return
		}

		let conversation = pending?.conversation
		let incomplete = contents.labeledDelivery.outcome == .failed || batchMessages.queuedEntries.values.contains {
			$0.rootBatch === contents && $0.batchIsOpen
		}
		var pageMessageCount = 0
		for queuedMessage in contents.queuedMessages {
			var message = queuedMessage
			let inPage = batch === contents || batchMessage(ofKind: .chatHistory, containing: message) === batch
			if inPage {
				pageMessageCount += 1
				guard !chatHistoryMessageIsDuplicate(message) else { continue }
				message.isReplayed = true
			}
			processIncomingMessage(message)
		}
		batchMessages.dequeueEntry(contents)
		guard let pending else { return }
		let lines = chatHistory.prependedLines ?? []
		chatHistory.prependConversation = nil
		chatHistory.prependedLines = nil
		let outcome: ServerHistoryOutcome = incomplete ? .failed(reason: nil) : .page(
			lines: lines, extent: pending.label != nil && pageMessageCount == 0 ? .exhausted : .unknown
		)
		guard finishServerHistory(pending, outcome: outcome) else { return }
		if pending.delivery == .transcript, !incomplete {
			conversation?.presentation?.prependEarlierChatLines(lines)
		}
	}

	private func timeoutServerHistory(_ pending: PendingServerHistoryRequest) {
		guard chatHistory.serverRequests.values.contains(where: { $0 === pending }) else { return }
		guard pending.conversation != nil else {
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
	func finishServerHistory(_ pending: PendingServerHistoryRequest, outcome: ServerHistoryOutcome) -> Bool {
		guard let key = chatHistory.serverRequests.first(where: { $0.value === pending })?.key else { return false }
		chatHistory.serverRequests.removeValue(forKey: key)
		pending.timeoutTimer?.stop()
		pending.timeoutTimer = nil
		pending.presentation?.receiveServerHistory(outcome, for: pending.request)
		return true
	}
}
