// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/// Catch-up or gap-fill paging for one conversation, while it runs.
final class PendingChatHistoryPaging {
	enum Kind {
		case catchUp(ChatHistoryCatchUp)
		case gapFill(ChatHistoryGapFill)
	}

	var kind: Kind
	/// The label of the page in flight, or `nil` without labelled responses.
	var label: String?
	let connectionIdentifier: String?
	weak var conversation: Conversation?
	var timeoutTimer: SessionTimer?

	init(kind: Kind, conversation: Conversation, connectionIdentifier: String?) {
		self.kind = kind
		self.conversation = conversation
		self.connectionIdentifier = connectionIdentifier
	}

	isolated deinit { timeoutTimer?.stop() }
}

extension ChatHistoryPolicy {
	/// The label prefix of catch-up and gap-fill pages, apart from the scroll-back
	/// prefix so a page of one is never taken for the other.
	static let pagingLabelPrefix = "paging-"
	/// How many full pages a catch-up or a gap fill asks for before it stops.
	static let maximumPagingPages = 10
}

extension ServerSession {
	/** Catches `conversation` up after it was joined or opened.

	 From the newest line known, by message identifier where the server takes
	 those and by time otherwise, `AFTER` pages arrive oldest first and are drawn
	 at the end like any replay. With nothing known, the latest page is asked
	 for, as before. */
	func requestChatHistoryCatchUp(for conversation: Conversation) {
		let key = conversation.uniqueIdentifier
		guard chatHistory.paging[key] == nil else { return }
		let messageIdentifier = conversation.presentation?.newestMessageIdentifier(sentBy: { _ in true })
		let known = ChatHistoryReference.preferred(
			messageIdentifier: messageIdentifier,
			timestamp: newestKnownServerTimestamp(for: conversation),
			support: chatHistoryReferenceSupport
		)
		/* A scroll-back page in flight keeps the slot: the catch-up would answer
		 to the same batch target, so the plain request goes out instead. */
		guard known != nil, chatHistory.serverRequests[key] == nil else {
			sendPlainLatest(for: conversation)
			return
		}
		var catchUp = ChatHistoryCatchUp(
			target: conversation.name,
			known: known,
			limit: chatHistoryRequestLimit(),
			maximumPages: ChatHistoryPolicy.maximumPagingPages
		)
		let step = catchUp.start()
		let paging = PendingChatHistoryPaging(
			kind: .catchUp(catchUp),
			conversation: conversation,
			connectionIdentifier: socket?.uniqueIdentifier
		)
		chatHistory.paging[key] = paging
		perform(step, for: paging)
	}

	private func sendPlainLatest(for conversation: Conversation) {
		guard let arguments = chatHistoryLatestArguments(target: conversation.name, since: nil) else { return }
		send(.chathistory, arguments: arguments)
	}

	/** Asks for the messages a catch-up could not reach. The lines are stored
	 rather than drawn at the end, and the transcript shows them where they
	 fall. Reports whether a fill started. */
	@discardableResult
	func fillChatHistoryGap(in conversation: Conversation) -> Bool {
		let key = conversation.uniqueIdentifier
		guard let gap = chatHistory.gaps[key], chatHistory.paging[key] == nil,
		      chatHistory.serverRequests[key] == nil, chatHistoryIsAvailable(for: conversation)
		else { return false }
		let fill = ChatHistoryGapFill(
			target: conversation.name,
			gap: gap,
			limit: chatHistoryRequestLimit(),
			maximumPages: ChatHistoryPolicy.maximumPagingPages
		)
		let paging = PendingChatHistoryPaging(
			kind: .gapFill(fill),
			conversation: conversation,
			connectionIdentifier: socket?.uniqueIdentifier
		)
		chatHistory.paging[key] = paging
		conversation.presentation?.noteMissingServerHistory(.loading)
		perform(fill.start(), for: paging)
		return true
	}

	/// Whether `conversation` is missing messages a fill could load.
	func hasChatHistoryGap(in conversation: Conversation) -> Bool {
		chatHistory.gaps[conversation.uniqueIdentifier] != nil
	}

	private func perform(_ step: ChatHistoryPagingStep, for paging: PendingChatHistoryPaging) {
		guard let conversation = paging.conversation else {
			endPaging(paging, failure: nil)
			return
		}
		switch step {
		case let .send(command):
			guard let arguments = chatHistoryArguments(command) else {
				endPaging(paging, failure: nil)
				return
			}
			let label = labeledResponseTrackingEnabled() ? ChatHistoryPolicy.pagingLabelPrefix + UUID().uuidString : nil
			paging.label = label
			paging.timeoutTimer?.stop()
			paging.timeoutTimer = SessionTimer.once(after: ChatHistoryPolicy.requestTimeout) { [weak self, weak paging] in
				guard let self, let paging else { return }
				endPaging(paging, failure: nil)
			}
			sendCommand(.chathistory, arguments: arguments, tags: label.map { ["label": $0] })
		case .finished:
			finishPaging(paging, remainingGap: nil, in: conversation)
		case let .finishedWithGap(gap):
			finishPaging(paging, remainingGap: gap, in: conversation)
		}
	}

	private func finishPaging(_ paging: PendingChatHistoryPaging, remainingGap: ChatHistoryGap?, in conversation: Conversation) {
		removePaging(paging)
		let key = conversation.uniqueIdentifier
		if let remainingGap {
			chatHistory.gaps[key] = remainingGap
			conversation.presentation?.noteMissingServerHistory(.missing)
		} else if case .gapFill = paging.kind {
			chatHistory.gaps[key] = nil
			conversation.presentation?.noteMissingServerHistory(.none)
		}
	}

	/// Ends paging that failed or timed out. A catch-up leaves no gap behind;
	/// a gap fill keeps its gap and says why it stopped.
	func endPaging(_ paging: PendingChatHistoryPaging, failure reason: String?) {
		removePaging(paging)
		guard case .gapFill = paging.kind, let conversation = paging.conversation else { return }
		conversation.presentation?.noteMissingServerHistory(.failed(reason: reason))
	}

	private func removePaging(_ paging: PendingChatHistoryPaging) {
		paging.timeoutTimer?.stop()
		paging.timeoutTimer = nil
		guard let key = chatHistory.paging.first(where: { $0.value === paging })?.key else { return }
		chatHistory.paging.removeValue(forKey: key)
	}

	/// The paging a `chathistory` batch answers: by label where there is one,
	/// and by its target otherwise.
	func pagingAnswered(by batch: MessageBatch) -> PendingChatHistoryPaging? {
		let label = batch.labeledResponseBatch?.labeledDelivery.label
		return chatHistory.paging.values.first { paging in
			guard paging.connectionIdentifier == socket?.uniqueIdentifier, let conversation = paging.conversation else {
				return false
			}
			if let pagingLabel = paging.label {
				return label == pagingLabel
			}
			return label == nil && supportInfo.casefoldString(batch.batchParameters?.first ?? "")
				== supportInfo.casefoldString(conversation.name)
		}
	}

	/// The paging a failure answers, by label or by target.
	func pagingFailed(label: String?, target: String?) -> PendingChatHistoryPaging? {
		if let label {
			return chatHistory.paging.values.first { $0.label == label }
		}
		guard let target, let conversation = findConversation(target) else { return nil }
		let paging = chatHistory.paging[conversation.uniqueIdentifier]
		return paging?.label == nil ? paging : nil
	}

	/** Replays one page of catch-up or gap fill and moves the paging on.

	 A catch-up page is processed like any replay, so its lines are drawn at
	 the end. A gap-fill page is collected instead and handed to the transcript
	 to store, because its lines are older than what is drawn. */
	func replayPagingBatch(_ batch: MessageBatch, contents: MessageBatch, paging: PendingChatHistoryPaging) {
		paging.timeoutTimer?.stop()
		let incomplete = contents.labeledDelivery.outcome == .failed || batchMessages.queuedEntries.values.contains {
			$0.rootBatch === contents && $0.batchIsOpen
		}
		let conversation = paging.conversation
		let isGapFill = if case .gapFill = paging.kind {
			true
		} else {
			false
		}
		if isGapFill {
			chatHistory.prependConversation = conversation
			chatHistory.prependedLines = []
		}

		var count = 0
		var first: ChatHistoryReference?
		var last: ChatHistoryReference?
		for queuedMessage in contents.queuedMessages {
			var message = queuedMessage
			let inPage = batch === contents || batchMessage(ofKind: .chatHistory, containing: message) === batch
			if inPage {
				count += 1
				let reference = pageReference(for: message)
				first = first ?? reference
				last = reference ?? last
				guard !chatHistoryMessageIsDuplicate(message) else { continue }
				message.isReplayed = true
			}
			processIncomingMessage(message)
		}
		batchMessages.dequeueEntry(contents)

		let recovered = chatHistory.prependedLines ?? []
		if isGapFill {
			chatHistory.prependConversation = nil
			chatHistory.prependedLines = nil
			if recovered.isEmpty == false {
				conversation?.presentation?.archiveRecoveredChatLines(recovered)
			}
		}

		guard incomplete == false else {
			endPaging(paging, failure: nil)
			return
		}
		let step: ChatHistoryPagingStep
		switch paging.kind {
		case var .catchUp(catchUp):
			step = catchUp.receivedPage(count: count, first: first, last: last)
			paging.kind = .catchUp(catchUp)
		case var .gapFill(fill):
			step = fill.receivedPage(count: count, last: last)
			paging.kind = .gapFill(fill)
		}
		perform(step, for: paging)
	}

	/// The reference a later request can count from: the message identifier
	/// where the server takes those, and the server time otherwise.
	private func pageReference(for message: Message) -> ChatHistoryReference? {
		ChatHistoryReference.preferred(
			messageIdentifier: message.messageIdentifier,
			timestamp: message.receivedAt,
			support: chatHistoryReferenceSupport
		)
	}

	func resetChatHistoryPaging() {
		for paging in chatHistory.paging.values {
			paging.timeoutTimer?.stop()
		}
		chatHistory.paging.removeAll()
		let conversations = chatHistory.gaps.keys.compactMap { key in conversationList.first { $0.uniqueIdentifier == key } }
		chatHistory.gaps.removeAll()
		for conversation in conversations {
			conversation.presentation?.noteMissingServerHistory(.none)
		}
	}
}
