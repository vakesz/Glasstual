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

@objc(IRCMessageBatchMessageContainer)
public final class MessageBatchContainer: NSObject {
	private let lock = NSLock()
	private var entries: [String: MessageBatch] = [:]

	@objc public var queuedEntries: [String: MessageBatch] {
		lock.withLock { entries }
	}

	@objc(queueEntry:)
	public func queueEntry(_ entry: Any) {
		guard let entry = entry as? MessageBatch else {
			return
		}

		lock.withLock {
			entries[entry.batchToken] = entry
		}
	}

	@objc(dequeueEntry:)
	public func dequeueEntry(_ entry: Any) {
		lock.withLock {
			let batch: MessageBatch?
			let token: String

			if let entry = entry as? MessageBatch {
				batch = entry
				token = entry.batchToken
			} else if let entry = entry as? String {
				batch = entries[entry]
				token = entry
			} else {
				return
			}

			batch?.dequeueEntries()
			entries.removeValue(forKey: token)
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
	private let lock = NSLock()
	private var entries: [Any] = []

	@objc public var batchIsOpen = false
	@objc public var batchToken = ""
	@objc public var batchType: String?
	@objc public var batchParameters: [String]?
	@objc public weak var parentBatchMessage: MessageBatch?

	@objc public var queuedEntries: [Any] {
		lock.withLock { entries }
	}

	@objc(queueEntry:)
	public func queueEntry(_ entry: Any) {
		guard entry is Message || entry is MessageBatch else {
			return
		}

		lock.withLock {
			entries.append(entry)
		}
	}

	@objc(dequeueEntry:)
	public func dequeueEntry(_ entry: Any) {
		guard entry is Message || entry is MessageBatch else {
			return
		}

		lock.withLock {
			entries.removeAll { ($0 as AnyObject).isEqual(entry) }
		}
	}

	@objc public func dequeueEntries() {
		lock.withLock {
			entries.removeAll()
		}
	}
}
