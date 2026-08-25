import XCTest

// Preprocessor directives found in file:
// #import <XCTest/XCTest.h>
// #import "IRCMessage.h"
// #import "IRCMessageBatchPrivate.h"
/* *********************************************************************
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
class IRCMessageBatchTests: XCTestCase {
    @objc
    func batchWithToken(_ token: String) -> UnsafeMutablePointer<IRCMessageBatchMessage> {
        var batch: UnsafeMutablePointer<IRCMessageBatchMessage>! = IRCMessageBatchMessage()

        batch.batchToken = token

        return batch
    }
    @objc
    func testContainerQueuesAndDequeuesBatchesByToken() {
        let container: UnsafeMutablePointer<IRCMessageBatchMessageContainer>! = IRCMessageBatchMessageContainer()
        let batch = self.batchWithToken("history-1")
        let message: UnsafeMutablePointer<IRCMessage>! = IRCMessage(line: ":nick!user@host PRIVMSG #channel :hello")

        batch.queueEntry(message)

        container.queueEntry(batch)

        XCTAssertEqual(container.queuedEntryWithBatchToken("history-1"), batch)

        XCTAssertEqualObjects(container.queuedEntries, ["history-1": batch])
        XCTAssertEqualObjects(batch.queuedEntries, [message])

        container.dequeueEntry("history-1")

        XCTAssertNil(container.queuedEntryWithBatchToken("history-1"))

        XCTAssertEqual(batch.queuedEntries.count, 0)
    }
    @objc
    func testBatchAcceptsMessagesAndNestedBatchesOnly() {
        let parent = self.batchWithToken("parent")
        var child = self.batchWithToken("child")
        let first: UnsafeMutablePointer<IRCMessage>! = IRCMessage(line: "PING :first")
        let second: UnsafeMutablePointer<IRCMessage>! = IRCMessage(line: "PING :second")

        child.parentBatchMessage = parent

        parent.queueEntry(first)
        parent.queueEntry(first)
        parent.queueEntry("invalid")
        parent.queueEntry(child)
        parent.queueEntry(second)

        XCTAssertEqualObjects(parent.queuedEntries, [first, first, child, second])

        XCTAssertEqual(child.parentBatchMessage, parent)

        parent.dequeueEntry(first)
        parent.dequeueEntry(child)

        XCTAssertEqualObjects(parent.queuedEntries, [second])
    }
    @objc
    func testContainerIgnoresNonBatchEntriesAndDequeueAllKeepsBatchContents() {
        let container: UnsafeMutablePointer<IRCMessageBatchMessageContainer>! = IRCMessageBatchMessageContainer()
        let batch = self.batchWithToken("batch")
        let message: UnsafeMutablePointer<IRCMessage>! = IRCMessage(line: "PING :token")

        batch.queueEntry(message)

        container.queueEntry("invalid")
        container.queueEntry(batch)
        container.dequeueEntries()

        XCTAssertEqual(container.queuedEntries.count, 0)

        XCTAssertEqualObjects(batch.queuedEntries, [message])
    }
}