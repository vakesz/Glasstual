// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/** One page of scroll-back, as the transcript asks for it.

 A `CHATHISTORY BEFORE` is the only request whose answer a view waits on, so
 these three values and the callback they travel with are what the protocol
 layer and the transcript agree on. They sat with the tree-item presentation
 protocol, which every tree item conforms to and only one of them wants. */
struct ServerHistoryRequest: Equatable {
	let id: UUID
	let before: Date
	let oldestLineNumber: String?
}

/// Whether the server has more to give before this page.
enum ServerHistoryPageExtent {
	case unknown
	/// The server answered with nothing, so this is the start of the history.
	case exhausted
}

enum ServerHistoryOutcome {
	case page(lines: [LogLine], extent: ServerHistoryPageExtent)
	case failed(reason: String?)
	case cancelled
}

/// Optional capability of a transcript presentation, not of every tree item.
@MainActor
protocol ServerHistoryPresentation: AnyObject {
	func receiveServerHistory(_ outcome: ServerHistoryOutcome, for request: ServerHistoryRequest)
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
	weak var channel: Channel?
	weak var presentation: (any ServerHistoryPresentation)?
	var cancelled = false
	var timeoutTask: Task<Void, Never>?

	init(request: ServerHistoryRequest, label: String?, channel: Channel, connectionIdentifier: String?,
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

@MainActor
extension Client {
	@discardableResult
	func requestServerHistory(_ request: ServerHistoryRequest, in channel: Channel,
	                          presentation: (any ServerHistoryPresentation)? = nil) -> Bool
	{
		guard serverHistoryRequestIsAdmissible(for: channel) else { return false }
		let requestLabel = ChatHistoryPolicy.requestLabelPrefix + request.id.uuidString
		let label = labeledResponseTrackingEnabled() ? requestLabel : nil
		let pending = PendingServerHistoryRequest(
			request: request, label: label, channel: channel, connectionIdentifier: socket?.uniqueIdentifier,
			presentation: presentation
		)
		chatHistory.serverRequests[channel.uniqueIdentifier] = pending
		pending.timeoutTask = Task { [weak self, weak pending] in
			try? await Task.sleep(for: .seconds(ChatHistoryPolicy.requestTimeout))
			guard !Task.isCancelled, let self, let pending else { return }
			timeoutServerHistory(pending)
		}
		sendCommand(
			chatHistoryCommand,
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
	func canRetryServerHistory(for channel: Channel) -> Bool {
		serverHistoryRequestIsAdmissible(for: channel)
	}

	private func serverHistoryRequestIsAdmissible(for channel: Channel) -> Bool {
		!isTerminating && chatHistoryIsAvailable(for: channel)
			&& chatHistory.serverRequests[channel.uniqueIdentifier] == nil
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
			pending.timeoutTask?.cancel()
			pending.presentation = nil
		}
	}

	func associateServerHistoryRequest(with batch: MessageBatch) {
		guard BatchPolicy.isChatHistory(batch.batchType), let target = batch.batchParameters?.first,
		      let channel = findChannel(target), let pending = chatHistory.serverRequests[channel.uniqueIdentifier],
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

		return label?.hasPrefix(ChatHistoryPolicy.requestLabelPrefix) == true
	}

	func replayChatHistoryBatch(_ batch: MessageBatch, contents: MessageBatch) {
		let pending = chatHistory.serverRequests.values.first { $0.request.id == batch.serverHistoryRequestID }

		if let pending {
			guard batchStillAnswers(pending, batch: batch) else {
				finishServerHistory(pending, outcome: .cancelled)
				batchMessages.dequeueEntry(contents)
				return
			}

			chatHistory.prependChannel = pending.channel
			chatHistory.prependedLines = []
		} else if batchOutlivedItsRequest(batch) {
			batchMessages.dequeueEntry(contents)
			return
		}

		let channel = pending?.channel
		let incomplete = contents.deliveryState == .failed || batchMessages.queuedEntries.values.contains {
			$0.rootBatch === contents && $0.batchIsOpen
		}
		var pageMessageCount = 0
		for message in contents.queuedMessages {
			let inPage = batch === contents || batchMessage(ofType: "chathistory", containing: message) === batch
			if inPage {
				pageMessageCount += 1
				guard !chatHistoryMessageIsDuplicate(message) else { continue }
				message.isHistoric = true
			}
			processIncomingMessage(message)
		}
		batchMessages.dequeueEntry(contents)
		guard let pending else { return }
		let lines = chatHistory.prependedLines ?? []
		chatHistory.prependChannel = nil
		chatHistory.prependedLines = nil
		let outcome: ServerHistoryOutcome = incomplete ? .failed(reason: nil) : .page(
			lines: lines, extent: pending.label != nil && pageMessageCount == 0 ? .exhausted : .unknown
		)
		guard finishServerHistory(pending, outcome: outcome) else { return }
		if pending.delivery == .transcript, !incomplete {
			channel?.presentation?.prependHistoricLogLines(lines)
		}
	}

	private func timeoutServerHistory(_ pending: PendingServerHistoryRequest) {
		guard chatHistory.serverRequests.values.contains(where: { $0 === pending }) else { return }
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
	func finishServerHistory(_ pending: PendingServerHistoryRequest, outcome: ServerHistoryOutcome) -> Bool {
		guard let key = chatHistory.serverRequests.first(where: { $0.value === pending })?.key else { return false }
		chatHistory.serverRequests.removeValue(forKey: key)
		pending.timeoutTask?.cancel()
		pending.timeoutTask = nil
		pending.presentation?.receiveServerHistory(outcome, for: pending.request)
		return true
	}
}
