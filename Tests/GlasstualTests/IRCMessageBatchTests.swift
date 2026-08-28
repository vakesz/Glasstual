@testable import Glasstual
import XCTest

/// Preprocessor directives found in file:
/// #import <XCTest/XCTest.h>
/// #import "IRCMessage.h"
/** *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\\__|\__,_|\__,_|_|
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
@objc
@MainActor
class IRCMessageBatchTests: XCTestCase {
	@objc
	func batchWithToken(_ token: String) -> MessageBatch {
		let batch = MessageBatch()

		batch.batchToken = token

		return batch
	}

	@objc
	func testContainerQueuesAndDequeuesBatchesByToken() {
		let container = MessageBatchContainer()
		let batch = batchWithToken("history-1")
		guard let message = Message(line: ":nick!user@host PRIVMSG #channel :hello") else {
			XCTFail("Expected a valid IRC message")
			return
		}

		batch.queueEntry(message)

		container.queueEntry(batch)

		XCTAssertTrue(container.queuedEntry(withBatchToken: "history-1") === batch)

		XCTAssertTrue(container.queuedEntries["history-1"] === batch)
		XCTAssertTrue(batch.queuedEntries.first as? Message === message)

		container.dequeueEntry("history-1")

		XCTAssertNil(container.queuedEntry(withBatchToken: "history-1"))

		XCTAssertEqual(batch.queuedEntries.count, 0)
	}

	@objc
	func testBatchAcceptsMessagesAndNestedBatchesOnly() {
		let parent = batchWithToken("parent")
		let child = batchWithToken("child")
		guard
			let first = Message(line: "PING :first"),
			let second = Message(line: "PING :second")
		else {
			XCTFail("Expected valid IRC messages")
			return
		}

		child.parentBatchMessage = parent

		parent.queueEntry(first)
		parent.queueEntry(first)
		parent.queueEntry("invalid")
		parent.queueEntry(child)
		parent.queueEntry(second)

		XCTAssertEqual(parent.queuedEntries.count, 4)
		XCTAssertTrue(parent.queuedEntries[0] as? Message === first)
		XCTAssertTrue(parent.queuedEntries[1] as? Message === first)
		XCTAssertTrue(parent.queuedEntries[2] as? MessageBatch === child)
		XCTAssertTrue(parent.queuedEntries[3] as? Message === second)

		XCTAssertTrue(child.parentBatchMessage === parent)

		parent.dequeueEntry(first)
		parent.dequeueEntry(child)

		XCTAssertTrue(parent.queuedEntries.first as? Message === second)
	}

	@objc
	func testContainerIgnoresNonBatchEntriesAndDequeueAllKeepsBatchContents() {
		let container = MessageBatchContainer()
		let batch = batchWithToken("batch")
		guard let message = Message(line: "PING :token") else {
			XCTFail("Expected a valid IRC message")
			return
		}

		batch.queueEntry(message)

		container.queueEntry("invalid")
		container.queueEntry(batch)
		container.dequeueEntries()

		XCTAssertEqual(container.queuedEntries.count, 0)

		XCTAssertTrue(batch.queuedEntries.first as? Message === message)
	}
}
