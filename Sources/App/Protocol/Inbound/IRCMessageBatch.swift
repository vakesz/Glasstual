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

/// What a batch can hold: a message, or a batch nested inside it.
public enum BatchEntry {
	case message(Message)
	case batch(MessageBatch)

	/// The entry as the object it wraps, for identity comparisons.
	var object: AnyObject {
		switch self {
		case let .message(message): message
		case let .batch(batch): batch
		}
	}
}

/// The batches a connection currently has open, keyed by their token.
///
/// Main-actor, like everything else that reads an inbound message, so the
/// entries need no lock of their own.
public final class MessageBatchContainer: NSObject {
	/// Each open batch holds its own queue, so the per-batch ceiling bounds
	/// nothing unless the number of open batches is bounded too. A server that
	/// opens batches and never closes them stops being able to open more.
	/// No network opens anywhere near this many at once.
	public static let maximumOpenBatches = 64

	private var entries: [String: MessageBatch] = [:]

	public var queuedEntries: [String: MessageBatch] {
		entries
	}

	/// `true` when the batch was registered; `false` when too many are open.
	@discardableResult
	public func queueEntry(_ entry: MessageBatch) -> Bool {
		guard entries[entry.batchToken] != nil || entries.count < MessageBatchContainer.maximumOpenBatches else {
			return false
		}

		entries[entry.batchToken] = entry

		return true
	}

	public func dequeueEntry(_ entry: MessageBatch) {
		dequeueEntry(withBatchToken: entry.batchToken)
	}

	public func dequeueEntry(withBatchToken token: String) {
		entries.removeValue(forKey: token)?.dequeueEntries()
	}

	public func dequeueEntries() {
		entries.removeAll()
	}

	public func queuedEntry(withBatchToken batchToken: String) -> MessageBatch? {
		entries[batchToken]
	}
}

public final class MessageBatch: NSObject {
	/// A batch the server never closes queues messages forever, so the queue
	/// is bounded. The ceiling is well above the largest chat-history replay
	/// any network offers.
	public static let maximumQueuedEntries = 5000

	private var entries: [BatchEntry] = []

	public var batchIsOpen = false
	public var batchToken = ""
	public var batchType: String?
	public var batchParameters: [String]?
	public weak var parentBatchMessage: MessageBatch?

	public var queuedEntries: [BatchEntry] {
		entries
	}

	/// `true` when the entry was accepted; `false` when the queue is full.
	@discardableResult
	public func queueEntry(_ entry: BatchEntry) -> Bool {
		guard entries.count < MessageBatch.maximumQueuedEntries else {
			return false
		}

		entries.append(entry)

		return true
	}

	@discardableResult
	public func queueEntry(_ message: Message) -> Bool {
		queueEntry(.message(message))
	}

	@discardableResult
	public func queueEntry(_ batch: MessageBatch) -> Bool {
		queueEntry(.batch(batch))
	}

	public func dequeueEntry(_ entry: BatchEntry) {
		let object = entry.object
		entries.removeAll { $0.object === object }
	}

	public func dequeueEntry(_ message: Message) {
		dequeueEntry(.message(message))
	}

	public func dequeueEntry(_ batch: MessageBatch) {
		dequeueEntry(.batch(batch))
	}

	public func dequeueEntries() {
		entries.removeAll()
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
