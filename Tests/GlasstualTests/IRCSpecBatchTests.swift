/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
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

/// IRCv3 `batch` and `labeled-response`.
@Suite("IRCv3 batch and labeled-response")
@MainActor
struct IRCSpecBatchTests {
	private func batchClient() -> GLTTestClient {
		let client = GLTTestClient(configDictionary: ["nickname": "me", "username": "me"])

		client.enableCapability(.batch)
		client.enableCapability(.messageTags)

		return client
	}

	private func message(_ line: String, on client: GLTTestClient) throws -> Message {
		try #require(Message(line: line, on: client))
	}

	/// Replays the order the socket reader uses: the batch filter first, then
	/// `BATCH` itself, then ordinary dispatch.
	@discardableResult
	private func feed(_ line: String, on client: GLTTestClient) throws -> Bool {
		let message = try message(line, on: client)

		if client.filterBatchCommandIncomingData(message) {
			return true
		}

		if message.command == "BATCH" {
			client.receiveBatch(message)
		} else {
			client.processIncomingMessage(message)
		}

		return false
	}

	// MARK: - The BATCH reference tag

	/// `batch`: "The reference tag ... MUST consist only of `a-z`, `A-Z`,
	/// `0-9`, `-` and `_`", and it is introduced by a `+` and retired by a `-`.
	@Test(
		"batch: a well-formed reference opens or closes",
		arguments: [
			("+abc", true), ("-abc", false), ("+A_1-2", true), ("-A_1-2", false),
		]
	)
	func wellFormedReferencesAreRead(_ testCase: (reference: String, opens: Bool)) throws {
		let parsed = try #require(IRCBatchPolicy.normalizedToken(testCase.reference))

		#expect(parsed.opens == testCase.opens)
		#expect(parsed.token == String(testCase.reference.dropFirst()))
	}

	/// A reference outside that alphabet, or with no modifier, is not a batch
	/// reference and must not open one.
	@Test(
		"batch: a malformed reference opens nothing",
		arguments: ["", "+", "-", "abc", "+a.b", "+a b", "*abc", "+a/b"]
	)
	func malformedReferencesAreRejected(_ reference: String) {
		#expect(IRCBatchPolicy.normalizedToken(reference) == nil)
	}

	/// `batch`: `BATCH +<reference> <type> [params...]`.
	@Test("batch: an opening BATCH records its type and parameters")
	func openingBatchRecordsTypeAndParameters() throws {
		let client = batchClient()

		try feed(":irc.example.net BATCH +ref chathistory #chan", on: client)

		let batch = try #require(client.queuedBatchMessage(withToken: "ref") as? MessageBatch)

		#expect(batch.batchIsOpen)
		#expect(batch.batchType == "chathistory")
		#expect(batch.batchParameters == ["#chan"])
	}

	// MARK: - Membership of a batch

	/// `batch`: a message tagged with an open reference belongs to that batch
	/// and is held rather than processed as it arrives.
	@Test("batch: a tagged message is held until the batch closes")
	func taggedMessagesAreHeldUntilTheBatchCloses() throws {
		let client = batchClient()

		client.markAsLoggedIn()

		try feed(":irc.example.net BATCH +ref netjoin", on: client)

		#expect(try feed("@batch=ref :alice!a@h JOIN #chan", on: client))
		#expect(client.processedMessages.count == 0)

		let batch = try #require(client.queuedBatchMessage(withToken: "ref") as? MessageBatch)

		#expect(batch.queuedEntries.count == 1)
	}

	/// `batch`: "If the client receives a message with a batch tag naming a
	/// reference it does not know about, it SHOULD process the message as
	/// normal" — an orphaned reference must not swallow traffic.
	@Test("batch: a message naming an unknown reference is processed normally")
	func orphanedBatchReferencesAreProcessedNormally() throws {
		let client = batchClient()

		#expect(try feed("@batch=unknown :alice!a@h PRIVMSG #chan :hi", on: client) == false)
		#expect(client.processedMessages.count == 1)
	}

	/// The same holds once a batch has closed: its reference is retired, and a
	/// straggler naming it is ordinary traffic.
	@Test("batch: a message naming a closed reference is processed normally")
	func closedBatchReferencesAreProcessedNormally() throws {
		let client = batchClient()

		client.markAsLoggedIn()

		try feed(":irc.example.net BATCH +ref netjoin", on: client)
		try feed(":irc.example.net BATCH -ref", on: client)

		#expect(try feed("@batch=ref :alice!a@h PRIVMSG #chan :hi", on: client) == false)
	}

	/// A closing reference the client never opened says nothing; it must not
	/// be mistaken for the end of some other batch.
	@Test("batch: closing an unknown reference does nothing")
	func closingAnUnknownReferenceDoesNothing() throws {
		let client = batchClient()

		try feed(":irc.example.net BATCH +ref netjoin", on: client)
		try feed(":irc.example.net BATCH -other", on: client)

		let batch = try #require(client.queuedBatchMessage(withToken: "ref") as? MessageBatch)

		#expect(batch.batchIsOpen)
	}

	/// `batch`: the `batch` tag only means anything once the capability is
	/// negotiated. Without it, a tagged message is ordinary traffic.
	@Test("batch: the tag is ignored without the capability")
	func batchTagNeedsTheCapability() throws {
		let client = GLTTestClient(configDictionary: ["nickname": "me"])
		let message = try message("@batch=ref :alice!a@h PRIVMSG #chan :hi", on: client)

		#expect(message.batchToken == nil)
	}

	// MARK: - Nesting

	/// `batch`: "Batches can be nested" — an inner `BATCH` carries the outer
	/// reference as its own tag, and the client has to remember the parent.
	@Test("batch: a nested batch remembers its parent")
	func nestedBatchesRememberTheirParent() throws {
		let client = batchClient()

		try feed(":irc.example.net BATCH +outer chathistory #chan", on: client)
		try feed("@batch=outer :irc.example.net BATCH +inner netsplit a b", on: client)

		let outer = try #require(client.queuedBatchMessage(withToken: "outer") as? MessageBatch)
		let inner = try #require(client.queuedBatchMessage(withToken: "inner") as? MessageBatch)

		#expect(inner.parentBatchMessage === outer)
		#expect(inner.batchType == "netsplit")
	}

	/// A message inside a nested batch belongs to the outermost one for replay
	/// purposes: the whole tree is played back when the outer batch closes, so
	/// the inner content must not be lost when the inner reference retires.
	@Test("batch: a message inside a nested batch survives the inner close")
	func nestedContentSurvivesTheInnerClose() throws {
		let client = batchClient()

		client.markAsLoggedIn()

		try feed(":irc.example.net BATCH +outer chathistory #chan", on: client)
		try feed("@batch=outer :irc.example.net BATCH +inner netsplit a b", on: client)
		try feed("@batch=inner :alice!a@h QUIT :*.net *.split", on: client)
		try feed(":irc.example.net BATCH -inner", on: client)

		let outer = try #require(client.queuedBatchMessage(withToken: "outer") as? MessageBatch)

		#expect(outer.queuedEntries.count == 1)
	}

	/// A batch may not be nested without bound: a server that keeps opening
	/// children would otherwise drive an unbounded walk on every message.
	@Test("batch: nesting depth is bounded")
	func nestingDepthIsBounded() {
		#expect(IRCBatchPolicy.maximumParentDepth == 16)
	}

	/// A batch may not grow without bound either — chathistory replies are
	/// server-sized, and one batch must not be able to exhaust memory.
	@Test("batch: a batch holds a bounded number of entries")
	func batchSizeIsBounded() {
		#expect(MessageBatch.maximumQueuedEntries == 5000)
	}

	/// The types the client replays specially, spelled as the specifications
	/// write them, including the `draft/` form chathistory shipped under.
	@Test("batch: the types the client treats specially")
	func specialBatchTypesAreRecognised() {
		#expect(IRCBatchPolicy.isChatHistory("chathistory"))
		#expect(IRCBatchPolicy.isChatHistory("draft/chathistory"))
		#expect(IRCBatchPolicy.isChatHistory("netsplit") == false)
		#expect(IRCBatchPolicy.isNetsplit("netsplit"))
		#expect(IRCBatchPolicy.isNetsplit("netjoin"))
		#expect(IRCBatchPolicy.isNetsplit(nil) == false)
	}

	// MARK: - labeled-response

	private func labelledClient() -> GLTTestClient {
		let client = GLTTestClient(configDictionary: ["nickname": "me", "username": "me"])

		client.enableCapability(.messageTags)
		client.enableCapability(.echoMessage)
		client.enableCapability(.labeledResponse)

		return client
	}

	/// `labeled-response`: the client puts a `label` tag on the command and
	/// the server puts the same label on whatever it sends back.
	@Test("labeled-response: an echoed message resolves its label")
	func echoedMessageResolvesItsLabel() throws {
		let client = labelledClient()
		let channel = try #require(client.findChannelOrCreate("#chan"))
		let label = try #require(client.registerPendingDelivery(for: channel))

		#expect(client.deliveryState(forLabel: label) == .pending)

		let echo = try message("@label=\(label);msgid=abc :me!u@h PRIVMSG #chan :hi", on: client)

		#expect(client.resolveLabeledResponse(for: echo))
		#expect(client.deliveryState(forLabel: label) == .none)
	}

	/// `labeled-response`: "If the server has no response to send, it MUST
	/// send `ACK`" — which resolves the label just as an echo would.
	@Test("labeled-response: ACK resolves a label with no other response")
	func acknowledgementResolvesTheLabel() throws {
		let client = labelledClient()
		let channel = try #require(client.findChannelOrCreate("#chan"))
		let label = try #require(client.registerPendingDelivery(for: channel))
		let ack = try message("@label=\(label) ACK", on: client)

		#expect(client.resolveLabeledResponse(for: ack))
		#expect(client.deliveryState(forLabel: label) == .none)
	}

	/// A `FAIL` carrying the label says the command did not happen.
	@Test("labeled-response: a labelled FAIL resolves the label as a failure")
	func labelledFailureResolvesTheLabel() throws {
		let client = labelledClient()
		let channel = try #require(client.findChannelOrCreate("#chan"))
		let label = try #require(client.registerPendingDelivery(for: channel))
		let failure = try message(
			"@label=\(label) FAIL PRIVMSG ACCOUNT_REQUIRED_TO_MESSAGE :log in first",
			on: client
		)

		#expect(client.resolveLabeledResponse(for: failure))
		#expect(client.deliveryState(forLabel: label) == .none)
	}

	/// A label the client never issued, or has already resolved, must not
	/// consume the message: the dispatcher drops whatever this claims.
	@Test("labeled-response: an unknown label does not consume the message")
	func unknownLabelsDoNotConsumeTheMessage() throws {
		let client = labelledClient()
		let stray = try message("@label=g99 :me!u@h PRIVMSG #chan :hi", on: client)

		#expect(client.resolveLabeledResponse(for: stray) == false)
	}

	/// `labeled-response`: a response that is more than one message comes in a
	/// batch whose opening `BATCH` carries the label, so every message in the
	/// batch belongs to that label.
	@Test("labeled-response: a labelled batch resolves when it closes")
	func labelledBatchResolvesWhenItCloses() throws {
		let client = labelledClient()

		client.enableCapability(.batch)

		let channel = try #require(client.findChannelOrCreate("#chan"))
		let label = try #require(client.registerPendingDelivery(for: channel))
		let opening = try message("@label=\(label) :irc.example.net BATCH +ref labeled-response", on: client)

		#expect(client.resolveLabeledResponse(for: opening) == false)
		#expect(client.deliveryState(forLabel: label) == .pending)

		let closing = try message(":irc.example.net BATCH -ref", on: client)

		#expect(client.resolveLabeledResponse(for: closing) == false)
		#expect(client.deliveryState(forLabel: label) == .none)
	}

	/// Labels are only issued when the client can actually correlate the
	/// answer, which needs `labeled-response` and `echo-message` both.
	@Test("labeled-response: no label is issued without the capabilities")
	func noLabelWithoutTheCapabilities() throws {
		let client = GLTTestClient(configDictionary: ["nickname": "me"])
		let channel = try #require(client.findChannelOrCreate("#chan"))

		#expect(client.registerPendingDelivery(for: channel) == nil)
	}

	/// Labels are unique within a connection; reusing one would let a stale
	/// answer resolve a live command.
	@Test("labeled-response: labels are not reused")
	func labelsAreNotReused() throws {
		let client = labelledClient()
		let channel = try #require(client.findChannelOrCreate("#chan"))

		let first = try #require(client.registerPendingDelivery(for: channel))
		let second = try #require(client.registerPendingDelivery(for: channel))

		#expect(first != second)
	}

	/// Which inbound commands can carry a label at all.
	@Test("labeled-response: the responses that resolve a label")
	func responseKindsAreClassified() {
		#expect(IRCLabeledResponsePolicy.responseKind(command: "ACK", commandNumeric: 0) == .acknowledgement)
		#expect(IRCLabeledResponsePolicy.responseKind(command: "FAIL", commandNumeric: 0) == .failure)
		#expect(IRCLabeledResponsePolicy.responseKind(command: "PRIVMSG", commandNumeric: 0) == .echo)
		#expect(IRCLabeledResponsePolicy.responseKind(command: "NOTICE", commandNumeric: 0) == .echo)
		#expect(IRCLabeledResponsePolicy.responseKind(command: "TAGMSG", commandNumeric: 0) == .echo)
		#expect(IRCLabeledResponsePolicy.responseKind(command: "JOIN", commandNumeric: 0) == .unrelated)
	}
}
