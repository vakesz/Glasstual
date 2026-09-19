// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
import os

enum BatchPolicy {
	static let maximumParentDepth = 16

	static func normalizedToken(_ reference: String) -> (token: String, opens: Bool)? {
		guard reference.count > 1, let modifier = reference.first, modifier == "+" || modifier == "-" else {
			return nil
		}
		let token = String(reference.dropFirst())
		let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_-"))
		guard token.unicodeScalars.allSatisfy(allowed.contains) else { return nil }
		return (token, modifier == "+")
	}

	static func isChatHistory(_ type: String?) -> Bool {
		type == "chathistory" || type == "draft/chathistory"
	}

	static func isNetsplit(_ type: String?) -> Bool {
		type == "netsplit" || type == "netjoin"
	}

	/// A batch whose contents were said before the session asked for them:
	/// `chathistory` (IRCv3) or a bouncer's `playback` batch (ZNC).
	static func isReplay(_ type: String?) -> Bool {
		isChatHistory(type) || type == "playback" || type == "znc.in/playback"
	}
}

private let batchProcessingLogger = Logger(
	subsystem: LogSubsystem.current,
	category: "MessageBatching"
)

extension ServerSession {
	/** Links a freshly parsed line to the batch its `batch` tag names.

	 Whether the line is replay is decided by the batch it sits in, not by the
	 fact that it carries a timestamp, so the batch's verdict is added to the
	 one the parser reached from `server-time` alone. */
	func resolveBatch(of message: inout Message) {
		guard let batchToken = message.batchToken,
		      let batch = batchMessages.queuedEntry(withBatchToken: batchToken)
		else { return }

		message.parentBatchMessage = batch

		if batch.isReplay {
			message.isReplayed = true
		}
	}

	func filterBatchCommandIncomingData(_ message: Message) -> Bool {
		guard message.remoteCommand != .batch,
		      let batchToken = message.batchToken,
		      let batch = batchMessages.queuedEntry(withBatchToken: batchToken),
		      batch.batchIsOpen
		else { return false }

		let rootBatch = batch.rootBatch

		guard rootBatch.hasOverflowed == false else {
			return false
		}

		if rootBatch.queueMessage(message) {
			return true
		}

		/* A full queue used to drop the message, so a netsplit wider than the
		 queue lost the QUITs past it and left those people listed in every
		 channel. What was queued is processed now, in order, and the rest of
		 the batch as it arrives: the batch loses its replay treatment, but no
		 line. Its labelled response, if any, can no longer be trusted. */
		rootBatch.hasOverflowed = true
		rootBatch.labeledDelivery.state = .failed
		batchProcessingLogger.error("A batch exceeded its queue limit; processing the rest of it as it arrives")

		let queued = rootBatch.queuedMessages
		rootBatch.dequeueMessages()
		for queuedMessage in queued {
			processIncomingMessage(queuedMessage)
		}

		return false
	}

	func receiveBatch(_ message: Message) {
		guard let reference = message.params.first,
		      let tokenInfo = BatchPolicy.normalizedToken(reference)
		else {
			batchProcessingLogger.error("Rejected malformed BATCH token")
			return
		}

		if tokenInfo.opens {
			openBatch(token: tokenInfo.token, message: message)
		} else {
			closeBatch(token: tokenInfo.token)
		}
	}

	/// Processes the messages a closed batch held back, in the order they
	/// arrived, and retires the batch.
	func processQueuedMessages(of batchMessage: MessageBatch) {
		guard !batchMessage.batchIsOpen else { return }
		for message in batchMessage.queuedMessages {
			processIncomingMessage(message)
		}
		batchMessages.dequeueEntry(batchMessage)
	}

	func batchMessage(ofType batchType: String, containing message: Message) -> MessageBatch? {
		var batch = message.parentBatchMessage
		var depth = 0
		while let current = batch, depth < BatchPolicy.maximumParentDepth {
			if current.batchType == batchType || current.batchType == "draft/\(batchType)" {
				return current
			}
			batch = current.parentBatchMessage
			depth += 1
		}
		return nil
	}
}

private extension ServerSession {
	func openBatch(token: String, message: Message) {
		let batch = MessageBatch()
		batch.batchIsOpen = true
		batch.batchToken = token
		batch.batchType = message.params.count > 1 ? message.params[1] : nil
		batch.batchParameters = message.params.count > 2 ? Array(message.params.dropFirst(2)) : nil
		if let parentToken = message.batchToken {
			guard let parent = batchMessages.queuedEntry(withBatchToken: parentToken),
			      parent.batchIsOpen else { return }
			var ancestor: MessageBatch? = parent
			var depth = 1
			while let current = ancestor {
				depth += 1
				guard depth <= BatchPolicy.maximumParentDepth else { return }
				ancestor = current.parentBatchMessage
			}
			batch.parentBatchMessage = parent
		}

		guard batchMessages.queueEntry(batch) else {
			batchProcessingLogger.error("Refused a duplicate BATCH token or a batch past the open-batch limit")
			return
		}

		if batch.batchType == ServerQuirks.ZNC.playbackBatchType {
			znc.isPlayingBackHistory = znc.isConnected
		} else if batch.batchType == ServerQuirks.ZNC.certificateInfoBatchType {
			znc.isSendingCertificateInfo = znc.isConnected
			if message.batchToken == nil {
				znc.certificateChainText = ""
			}
		}
		if isCapabilityEnabled(.labeledResponse), let label = message.messageTags?["label"], !label.isEmpty {
			batch.labeledDelivery.label = label
		}
		associateServerHistoryRequest(with: batch)
	}

	func closeBatch(token: String) {
		guard let batch = batchMessages.queuedEntry(withBatchToken: token) else {
			batchProcessingLogger.error("Cannot close unknown BATCH token")
			return
		}
		batch.batchIsOpen = false
		if batch.parentBatchMessage != nil {
			// Keep closed children admitted until the root replays. Messages retain
			// their immediate batch, whose parent and label must still be available.
			return
		}

		let family = batchMessages.queuedEntries.values.filter { $0.rootBatch === batch }
		let incomplete = batch.labeledDelivery.state == .failed || family.contains { $0.batchIsOpen }

		replay(batch, family: family)
		resolveDeliveries(in: family, incomplete: incomplete)
		endZNCPlaybackState(for: batch)
	}

	/// Hands the closed batch to whichever replay owns its type. A labelled
	/// response wrapping exactly one chat-history batch is that history page,
	/// so the wrapper's contents are what gets replayed.
	private func replay(_ batch: MessageBatch, family: [MessageBatch]) {
		let historyBatches = family.filter { BatchPolicy.isChatHistory($0.batchType) }
		let nestedHistory = historyBatches.first { $0.parentBatchMessage != nil }

		if let nestedHistory, historyBatches.count == 1 {
			replayChatHistoryBatch(nestedHistory, contents: batch)
		} else if BatchPolicy.isChatHistory(batch.batchType) {
			replayChatHistoryBatch(batch)
		} else if BatchPolicy.isNetsplit(batch.batchType) {
			replayNetsplitBatch(batch)
		} else {
			processQueuedMessages(of: batch)
		}
	}

	/** Answers every labelled member of the family and empties the queue.

	 A batch's final result is known only after every queued reply ran: in
	 particular an echo before FAIL must not commit success early, which is why
	 `incomplete` is settled by the caller rather than in here. The failures go
	 first because a label two members share resolves once, and the dictionary
	 the family came out of has no order of its own. */
	private func resolveDeliveries(in family: [MessageBatch], incomplete: Bool) {
		let failuresFirst = family.sorted { first, second in
			first.labeledDelivery.state == .failed && second.labeledDelivery.state != .failed
		}

		for member in failuresFirst {
			if let label = member.labeledDelivery.label {
				let memberFailed = incomplete || member.labeledDelivery.state == .failed
				resolveDelivery(
					withLabel: label,
					state: incomplete ? .failed : member.labeledDelivery.state,
					messageIdentifier: memberFailed ? nil : member.labeledDelivery.messageIdentifier,
					reason: member.labeledDelivery.failureReason
				)
			}
			batchMessages.dequeueEntry(member)
		}
	}

	private func endZNCPlaybackState(for batch: MessageBatch) {
		if batch.batchType == ServerQuirks.ZNC.playbackBatchType {
			znc.isPlayingBackHistory = false
		} else if batch.batchType == ServerQuirks.ZNC.certificateInfoBatchType {
			znc.isSendingCertificateInfo = false
		}
	}
}
