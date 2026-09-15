/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2010 - 2018 Codeux Software, LLC & respective contributors.
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

/// The batches a connection currently has open, keyed by their token.
///
/// Main-actor, like everything else that reads an inbound message, so the
/// entries need no lock of their own.
public final class MessageBatchContainer {
	/// Each open batch holds its own queue, so the per-batch ceiling bounds
	/// nothing unless the number of open batches is bounded too. A server that
	/// opens batches and never closes them stops being able to open more.
	/// No network opens anywhere near this many at once.
	public static let maximumOpenBatches = 64

	private var entries: [String: MessageBatch] = [:]

	public var queuedEntries: [String: MessageBatch] {
		entries
	}

	/// Rejects duplicate active tokens as well as batches beyond the ceiling.
	@discardableResult
	public func queueEntry(_ entry: MessageBatch) -> Bool {
		guard entries[entry.batchToken] == nil, entries.count < MessageBatchContainer.maximumOpenBatches else {
			return false
		}

		entries[entry.batchToken] = entry

		return true
	}

	public func dequeueEntry(_ entry: MessageBatch) {
		dequeueEntry(withBatchToken: entry.batchToken)
	}

	public func dequeueEntry(withBatchToken token: String) {
		entries.removeValue(forKey: token)?.dequeueMessages()
	}

	public func dequeueEntries() {
		// Queued messages retain their batch metadata until replay. Break those
		// back-references before dropping the connection's batch table.
		for batch in entries.values {
			batch.dequeueMessages()
		}
		entries.removeAll()
	}

	public func queuedEntry(withBatchToken batchToken: String) -> MessageBatch? {
		entries[batchToken]
	}
}

/** One open or closing `BATCH`, and the messages it is holding back.

 Messages are queued at the root of a nested family, in the order they arrived,
 and a nested batch reaches them through `parentBatchMessage`; no batch is ever
 queued inside another. */
public final class MessageBatch {
	/// A batch the server never closes queues messages forever, so the queue
	/// is bounded. The ceiling is well above the largest chat-history replay
	/// any network offers.
	public static let maximumQueuedEntries = 5000

	private var messages: [Message] = []

	/// Set once the queue has overflowed: what it held was processed there and
	/// then, and every later message of the batch is processed as it arrives.
	var hasOverflowed = false

	public var batchIsOpen = false
	public var batchToken = ""
	public var batchType: String?
	public var batchParameters: [String]?
	public weak var parentBatchMessage: MessageBatch?
	var responseLabel: String?
	var serverHistoryRequestID: UUID?
	var deliveryState: LogLineDeliveryState = .delivered
	var deliveryMessageIdentifier: String?
	var deliveryFailureReason: String?

	var labeledResponseBatch: MessageBatch? {
		var batch: MessageBatch? = self
		for _ in 0 ..< IRCBatchPolicy.maximumParentDepth {
			guard let current = batch else { return nil }
			if current.responseLabel != nil {
				return current
			}
			batch = current.parentBatchMessage
		}
		return nil
	}

	var rootBatch: MessageBatch {
		var root = self
		for _ in 0 ..< IRCBatchPolicy.maximumParentDepth {
			guard let parent = root.parentBatchMessage else { break }
			root = parent
		}
		return root
	}

	public var queuedMessages: [Message] {
		messages
	}

	/// `true` when the message was accepted; `false` when the queue is full.
	@discardableResult
	public func queueMessage(_ message: Message) -> Bool {
		guard messages.count < MessageBatch.maximumQueuedEntries else {
			return false
		}

		messages.append(message)

		return true
	}

	public func dequeueMessages() {
		messages.removeAll()
	}

	/// `true` when this batch, or one it is nested inside, replays lines that
	/// were said earlier. The walk is bounded the same way the rest of the
	/// batch code bounds it, so a server that reports a cycle cannot hang us.
	public var isReplay: Bool {
		var batch: MessageBatch? = self
		var depth = 0

		while let current = batch, depth < IRCBatchPolicy.maximumParentDepth {
			if IRCBatchPolicy.isReplay(current.batchType) {
				return true
			}

			batch = current.parentBatchMessage
			depth += 1
		}

		return false
	}
}
