// Copyright (c) 2010 - 2018 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/// The batches a connection currently has open, keyed by their token.
///
/// Main-actor, like everything else that reads an inbound message, so the
/// entries need no lock of their own.
final class MessageBatchContainer {
	/// Each open batch holds its own queue, so the per-batch ceiling bounds
	/// nothing unless the number of open batches is bounded too. A server that
	/// opens batches and never closes them stops being able to open more.
	/// No network opens anywhere near this many at once.
	static let maximumOpenBatches = 64

	private var entries: [String: MessageBatch] = [:]

	var queuedEntries: [String: MessageBatch] {
		entries
	}

	/// Rejects duplicate active tokens as well as batches beyond the ceiling.
	@discardableResult
	func queueEntry(_ entry: MessageBatch) -> Bool {
		guard entries[entry.batchToken] == nil, entries.count < MessageBatchContainer.maximumOpenBatches else {
			return false
		}

		entries[entry.batchToken] = entry

		return true
	}

	func dequeueEntry(_ entry: MessageBatch) {
		dequeueEntry(withBatchToken: entry.batchToken)
	}

	func dequeueEntry(withBatchToken token: String) {
		entries.removeValue(forKey: token)?.dequeueMessages()
	}

	func dequeueEntries() {
		// Queued messages retain their batch metadata until replay. Break those
		// back-references before dropping the connection's batch table.
		for batch in entries.values {
			batch.dequeueMessages()
		}
		entries.removeAll()
	}

	func queuedEntry(withBatchToken batchToken: String) -> MessageBatch? {
		entries[batchToken]
	}
}

/** One open or closing `BATCH`, and the messages it is holding back.

 Messages are queued at the root of a nested family, in the order they arrived,
 and a nested batch reaches them through `parentBatchMessage`; no batch is ever
 queued inside another.

 This is the inbound session's record of a batch rather than a wire value: it
 has identity, it is mutated as lines arrive, and the subsystems that answer a
 batch keep their own state on it. */
final class MessageBatch {
	/// A batch the server never closes queues messages forever, so the queue
	/// is bounded. The ceiling is well above the largest chat-history replay
	/// any network offers.
	static let maximumQueuedEntries = 5000

	private var messages: [Message] = []

	/// Set once the queue has overflowed: what it held was processed there and
	/// then, and every later message of the batch is processed as it arrives.
	var hasOverflowed = false

	var batchIsOpen = false
	var batchToken = ""
	var batchType: String?
	var batchParameters: [String]?
	weak var parentBatchMessage: MessageBatch?
	/// What the labelled-response subsystem is waiting on this batch for. The
	/// shape is ``BatchDeliveryState``, which that subsystem declares.
	var labeledDelivery = BatchDeliveryState()

	var labeledResponseBatch: MessageBatch? {
		var batch: MessageBatch? = self
		for _ in 0 ..< BatchPolicy.maximumParentDepth {
			guard let current = batch else { return nil }
			if current.labeledDelivery.label != nil {
				return current
			}
			batch = current.parentBatchMessage
		}
		return nil
	}

	var rootBatch: MessageBatch {
		var root = self
		for _ in 0 ..< BatchPolicy.maximumParentDepth {
			guard let parent = root.parentBatchMessage else { break }
			root = parent
		}
		return root
	}

	var queuedMessages: [Message] {
		messages
	}

	/// `true` when the message was accepted; `false` when the queue is full.
	@discardableResult
	func queueMessage(_ message: Message) -> Bool {
		guard messages.count < MessageBatch.maximumQueuedEntries else {
			return false
		}

		messages.append(message)

		return true
	}

	func dequeueMessages() {
		messages.removeAll()
	}

	/// `true` when this batch, or one it is nested inside, replays lines that
	/// were said earlier. The walk is bounded the same way the rest of the
	/// batch code bounds it, so a server that reports a cycle cannot hang us.
	var isReplay: Bool {
		var batch: MessageBatch? = self
		var depth = 0

		while let current = batch, depth < BatchPolicy.maximumParentDepth {
			if BatchPolicy.isReplay(current.batchType) {
				return true
			}

			batch = current.parentBatchMessage
			depth += 1
		}

		return false
	}
}
