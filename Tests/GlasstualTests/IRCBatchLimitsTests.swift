/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \\ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\\___/_/\\_\\__|\\__,_|\\__,_|_|
 *
 * Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
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
struct IRCBatchLimitsTests {
	private func message(_ line: String, on client: IRCClient) throws -> Message {
		try #require(Message(line: line, on: client))
	}

	private func closedBatch(token: String) -> MessageBatch {
		let batch = MessageBatch()
		batch.batchToken = token
		batch.batchIsOpen = false
		return batch
	}

	/// A batch the server never closes used to queue messages without limit.
	@Test
	func batchQueueRejectsEntriesPastItsCeiling() throws {
		let client = GLTTestClient()
		let batch = closedBatch(token: "full")

		for index in 0 ..< MessageBatch.maximumQueuedEntries {
			try #expect(batch.queueEntry(message(":a!u@h PRIVMSG #c :\(index)", on: client)))
		}

		#expect(batch.queuedEntries.count == MessageBatch.maximumQueuedEntries)
		try #expect(batch.queueEntry(message(":a!u@h PRIVMSG #c :overflow", on: client)) == false)
		#expect(batch.queuedEntries.count == MessageBatch.maximumQueuedEntries)
	}

	/// `depth` was declared and then ignored, so nested batches recursed
	/// without bound.
	@Test
	func nestedBatchesDeeperThanTheLimitAreNotProcessed() throws {
		let client = GLTTestClient()
		let batches = (0 ... IRCBatchPolicy.maximumParentDepth).map { closedBatch(token: "b\($0)") }

		for index in 0 ..< (batches.count - 1) {
			batches[index].queueEntry(batches[index + 1])
		}

		try batches[batches.count - 1].queueEntry(message(":a!u@h PRIVMSG #c :deep", on: client))

		client.recursivelyProcessBatchMessage(batches[0], depth: 0)

		#expect(client.processedMessages.count == 0)
	}

	@Test
	func shallowlyNestedBatchesAreStillProcessed() throws {
		let client = GLTTestClient()
		let outer = closedBatch(token: "outer")
		let inner = closedBatch(token: "inner")

		outer.queueEntry(inner)
		try inner.queueEntry(message(":a!u@h PRIVMSG #c :hello", on: client))

		client.recursivelyProcessBatchMessage(outer, depth: 0)

		#expect(client.processedMessages.count == 1)
	}
}

@MainActor
struct IRCMessageTagLimitTests {
	/// IRCv3 caps the tag section at 8191 bytes.
	@Test
	func oversizedTagSectionsAreDropped() {
		let oversized = "a=" + String(repeating: "b", count: 8191)

		#expect(MessageTagParser.parsedTags(fromSection: oversized).tags.isEmpty)
	}

	@Test
	func tagSectionsAtTheLimitAreStillParsed() {
		let value = String(repeating: "b", count: MessageTagParser.maximumSectionLength - 2)
		let section = "a=" + value

		#expect(section.utf8.count == MessageTagParser.maximumSectionLength)
		#expect(MessageTagParser.parsedTags(fromSection: section).tags == ["a": value])
	}
}

@MainActor
struct IRCClientSASLPayloadLimitTests {
	/// `saslIncomingPayload` grew 400 characters per AUTHENTICATE with no
	/// ceiling, so a server could grow it until the process died.
	@Test
	func oversizedSASLPayloadsAbortNegotiation() throws {
		let client = GLTTestClient()
		client.enableCapability(.isInSASLNegotiation)

		let chunk = String(repeating: "A", count: 400)
		let chunksBeforeOverflow = ClientNegotiationUtilities.maximumSASLPayloadLength / 400

		for _ in 0 ..< chunksBeforeOverflow {
			let message = try #require(Message(line: "AUTHENTICATE \(chunk)", on: client))
			client.receiveCapabilityOrAuthenticationRequest(message)
		}

		#expect(client.saslIncomingPayload?.count == chunksBeforeOverflow * 400)

		let overflow = try #require(Message(line: "AUTHENTICATE \(chunk)", on: client))
		client.receiveCapabilityOrAuthenticationRequest(overflow)

		#expect(client.saslIncomingPayload == nil)
	}
}
