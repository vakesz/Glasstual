/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \\ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\\___/_/\\_\\__|\\__,_|\\__,_|_|
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

public typealias IRCMessageBatchMessageContainer = MessageBatchContainer
public typealias IRCMessageBatchMessage = MessageBatch

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

@objc(IRCMessageBatchMessageContainer)
public final class MessageBatchContainer: NSObject {
	private let lock = NSLock()
	private var entries: [String: MessageBatch] = [:]

	@objc public var queuedEntries: [String: MessageBatch] {
		lock.withLock { entries }
	}

	public func queueEntry(_ entry: MessageBatch) {
		lock.withLock {
			entries[entry.batchToken] = entry
		}
	}

	public func dequeueEntry(_ entry: MessageBatch) {
		dequeueEntry(withBatchToken: entry.batchToken)
	}

	public func dequeueEntry(withBatchToken token: String) {
		lock.withLock {
			entries.removeValue(forKey: token)?.dequeueEntries()
		}
	}

	@objc public func dequeueEntries() {
		lock.withLock {
			entries.removeAll()
		}
	}

	@objc(queuedEntryWithBatchToken:)
	public func queuedEntry(withBatchToken batchToken: String) -> MessageBatch? {
		lock.withLock { entries[batchToken] }
	}
}

@objc(IRCMessageBatchMessage)
public final class MessageBatch: NSObject {
	/// A batch the server never closes queues messages forever, so the queue
	/// is bounded. The ceiling is well above the largest chat-history replay
	/// any network offers.
	@objc public static let maximumQueuedEntries = 5000

	private let lock = NSLock()
	private var entries: [BatchEntry] = []

	@objc public var batchIsOpen = false
	@objc public var batchToken = ""
	@objc public var batchType: String?
	@objc public var batchParameters: [String]?
	@objc public weak var parentBatchMessage: MessageBatch?

	public var queuedEntries: [BatchEntry] {
		lock.withLock { entries }
	}

	/// `true` when the entry was accepted; `false` when the queue is full.
	@discardableResult
	public func queueEntry(_ entry: BatchEntry) -> Bool {
		lock.withLock {
			guard entries.count < MessageBatch.maximumQueuedEntries else {
				return false
			}

			entries.append(entry)

			return true
		}
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
		lock.withLock {
			entries.removeAll { $0.object === object }
		}
	}

	public func dequeueEntry(_ message: Message) {
		dequeueEntry(.message(message))
	}

	public func dequeueEntry(_ batch: MessageBatch) {
		dequeueEntry(.batch(batch))
	}

	@objc public func dequeueEntries() {
		lock.withLock {
			entries.removeAll()
		}
	}
}
