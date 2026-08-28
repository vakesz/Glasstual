/*  *********************************************************************
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
@testable import Glasstual
import Testing

@MainActor
@Suite("IRC message batches")
struct IRCMessageBatchTests {
	@Test("A batch is found by its token until it is dequeued")
	func containerQueuesAndDequeuesBatchesByToken() throws {
		let container = MessageBatchContainer()
		let batch = batchWithToken("history-1")
		let message = try #require(Message(line: ":nick!user@host PRIVMSG #channel :hello"))

		batch.queueEntry(message)

		container.queueEntry(batch)

		#expect(container.queuedEntry(withBatchToken: "history-1") === batch)

		#expect(container.queuedEntries["history-1"] === batch)
		#expect(batch.queuedEntries.first?.object as? Message === message)

		container.dequeueEntry(withBatchToken: "history-1")

		#expect(container.queuedEntry(withBatchToken: "history-1") == nil)

		#expect(batch.queuedEntries.count == 0)
	}

	@Test("A batch keeps its messages and its nested batches in the order they arrived")
	func batchKeepsMessagesAndNestedBatchesInOrder() throws {
		let parent = batchWithToken("parent")
		let child = batchWithToken("child")
		let first = try #require(Message(line: "PING :first"))
		let second = try #require(Message(line: "PING :second"))

		child.parentBatchMessage = parent

		parent.queueEntry(first)
		parent.queueEntry(first)
		parent.queueEntry(child)
		parent.queueEntry(second)

		#expect(parent.queuedEntries.count == 4)
		#expect(parent.queuedEntries[0].object as? Message === first)
		#expect(parent.queuedEntries[1].object as? Message === first)
		#expect(parent.queuedEntries[2].object as? MessageBatch === child)
		#expect(parent.queuedEntries[3].object as? Message === second)

		#expect(child.parentBatchMessage === parent)

		parent.dequeueEntry(first)
		parent.dequeueEntry(child)

		#expect(parent.queuedEntries.first?.object as? Message === second)
	}

	@Test("Emptying the container leaves the batches it held with their contents")
	func dequeuingEveryBatchKeepsTheirContents() throws {
		let container = MessageBatchContainer()
		let batch = batchWithToken("batch")
		let message = try #require(Message(line: "PING :token"))

		batch.queueEntry(message)

		container.queueEntry(batch)
		container.dequeueEntries()

		#expect(container.queuedEntries.count == 0)

		#expect(batch.queuedEntries.first?.object as? Message === message)
	}

	private func batchWithToken(_ token: String) -> MessageBatch {
		let batch = MessageBatch()

		batch.batchToken = token

		return batch
	}
}
