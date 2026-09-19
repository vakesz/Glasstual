// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing

/// IRCv3 `batch` and `labeled-response`.
@Suite("IRCv3 batch and labeled-response")
@MainActor
struct IRCSpecBatchTests {
	private func batchSession() -> TestServerSession {
		let session = TestServerSession(configDictionary: ["nickname": "me", "username": "me"])

		session.enableCapability(.batch)
		session.enableCapability(.messageTags)

		return session
	}

	private func message(_ line: String, on session: TestServerSession) throws -> Message {
		try #require(Message(line: line, on: session))
	}

	/// Replays the order the socket reader uses: the batch filter first, then
	/// `BATCH` itself, then ordinary dispatch.
	@discardableResult
	private func feed(_ line: String, on session: TestServerSession) throws -> Bool {
		let message = try message(line, on: session)

		if session.filterBatchCommandIncomingData(message) {
			return true
		}

		if message.remoteCommand == .batch {
			session.receiveBatch(message)
		} else {
			session.processIncomingMessage(message)
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
		let parsed = try #require(BatchPolicy.normalizedToken(testCase.reference))

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
		#expect(BatchPolicy.normalizedToken(reference) == nil)
	}

	/// `batch`: `BATCH +<reference> <type> [params...]`.
	@Test("batch: an opening BATCH records its type and parameters")
	func openingBatchRecordsTypeAndParameters() throws {
		let session = batchSession()

		try feed(":irc.example.net BATCH +ref chathistory #chan", on: session)

		let batch = try #require(session.batchMessages.queuedEntry(withBatchToken: "ref"))

		#expect(batch.batchIsOpen)
		#expect(batch.batchType == "chathistory")
		#expect(batch.batchParameters == ["#chan"])
	}

	// MARK: - Membership of a batch

	/// `batch`: a message tagged with an open reference belongs to that batch
	/// and is held rather than processed as it arrives.
	@Test("batch: a tagged message is held until the batch closes")
	func taggedMessagesAreHeldUntilTheBatchCloses() throws {
		let session = batchSession()

		session.markAsLoggedIn()

		try feed(":irc.example.net BATCH +ref netjoin", on: session)

		#expect(try feed("@batch=ref :alice!a@h JOIN #chan", on: session))
		#expect(session.processedMessages.count == 0)

		let batch = try #require(session.batchMessages.queuedEntry(withBatchToken: "ref"))

		#expect(batch.queuedMessages.count == 1)
	}

	/// `batch`: "If the session receives a message with a batch tag naming a
	/// reference it does not know about, it SHOULD process the message as
	/// normal" — an orphaned reference must not swallow traffic.
	@Test("batch: a message naming an unknown reference is processed normally")
	func orphanedBatchReferencesAreProcessedNormally() throws {
		let session = batchSession()

		#expect(try feed("@batch=unknown :alice!a@h PRIVMSG #chan :hi", on: session) == false)
		#expect(session.processedMessages.count == 1)
	}

	/// The same holds once a batch has closed: its reference is retired, and a
	/// straggler naming it is ordinary traffic.
	@Test("batch: a message naming a closed reference is processed normally")
	func closedBatchReferencesAreProcessedNormally() throws {
		let session = batchSession()

		session.markAsLoggedIn()

		try feed(":irc.example.net BATCH +ref netjoin", on: session)
		try feed(":irc.example.net BATCH -ref", on: session)

		#expect(try feed("@batch=ref :alice!a@h PRIVMSG #chan :hi", on: session) == false)
	}

	/// A closing reference the session never opened says nothing; it must not
	/// be mistaken for the end of some other batch.
	@Test("batch: closing an unknown reference does nothing")
	func closingAnUnknownReferenceDoesNothing() throws {
		let session = batchSession()

		try feed(":irc.example.net BATCH +ref netjoin", on: session)
		try feed(":irc.example.net BATCH -other", on: session)

		let batch = try #require(session.batchMessages.queuedEntry(withBatchToken: "ref"))

		#expect(batch.batchIsOpen)
	}

	/// `batch`: the `batch` tag only means anything once the capability is
	/// negotiated. Without it, a tagged message is ordinary traffic.
	@Test("batch: the tag is ignored without the capability")
	func batchTagNeedsTheCapability() throws {
		let session = TestServerSession(configDictionary: ["nickname": "me"])
		let message = try message("@batch=ref :alice!a@h PRIVMSG #chan :hi", on: session)

		#expect(message.batchToken == nil)
	}

	// MARK: - Nesting

	/// `batch`: "Batches can be nested" — an inner `BATCH` carries the outer
	/// reference as its own tag, and the session has to remember the parent.
	@Test("batch: a nested batch remembers its parent")
	func nestedBatchesRememberTheirParent() throws {
		let session = batchSession()

		try feed(":irc.example.net BATCH +outer chathistory #chan", on: session)
		try feed("@batch=outer :irc.example.net BATCH +inner netsplit a b", on: session)

		let outer = try #require(session.batchMessages.queuedEntry(withBatchToken: "outer"))
		let inner = try #require(session.batchMessages.queuedEntry(withBatchToken: "inner"))

		#expect(inner.parentBatchMessage === outer)
		#expect(inner.batchType == "netsplit")
	}

	/// A message inside a nested batch belongs to the outermost one for replay
	/// purposes: the whole tree is played back when the outer batch closes, so
	/// the inner content must not be lost when the inner reference retires.
	@Test("batch: a message inside a nested batch survives the inner close")
	func nestedContentSurvivesTheInnerClose() throws {
		let session = batchSession()

		session.markAsLoggedIn()

		try feed(":irc.example.net BATCH +outer chathistory #chan", on: session)
		try feed("@batch=outer :irc.example.net BATCH +inner netsplit a b", on: session)
		try feed("@batch=inner :alice!a@h QUIT :*.net *.split", on: session)
		try feed(":irc.example.net BATCH -inner", on: session)

		let outer = try #require(session.batchMessages.queuedEntry(withBatchToken: "outer"))

		#expect(outer.queuedMessages.count == 1)
	}

	/// A batch may not be nested without bound: a server that keeps opening
	/// children would otherwise drive an unbounded walk on every message.
	@Test("batch: nesting depth is bounded")
	func nestingDepthIsBounded() {
		#expect(BatchPolicy.maximumParentDepth == 16)
	}

	/// A batch may not grow without bound either — chathistory replies are
	/// server-sized, and one batch must not be able to exhaust memory.
	@Test("batch: a batch holds a bounded number of entries")
	func batchSizeIsBounded() {
		#expect(MessageBatch.maximumQueuedEntries == 5000)
	}

	/// The types the session replays specially, spelled as the specifications
	/// write them, including the `draft/` form chathistory shipped under.
	@Test("batch: the types the session treats specially")
	func specialBatchTypesAreRecognised() {
		#expect(BatchPolicy.isChatHistory("chathistory"))
		#expect(BatchPolicy.isChatHistory("draft/chathistory"))
		#expect(BatchPolicy.isChatHistory("netsplit") == false)
		#expect(BatchPolicy.isNetsplit("netsplit"))
		#expect(BatchPolicy.isNetsplit("netjoin"))
		#expect(BatchPolicy.isNetsplit(nil) == false)
	}

	// MARK: - labeled-response

	private func labelledSession() -> TestServerSession {
		let session = TestServerSession(configDictionary: ["nickname": "me", "username": "me"])

		session.enableCapability(.messageTags)
		session.enableCapability(.echoMessage)
		session.enableCapability(.labeledResponse)

		return session
	}

	/// `labeled-response`: the session puts a `label` tag on the command and
	/// the server puts the same label on whatever it sends back.
	@Test("labeled-response: an echoed message resolves its label")
	func echoedMessageResolvesItsLabel() throws {
		let session = labelledSession()
		let channel = try #require(session.findConversationOrCreate("#chan"))
		let label = try #require(session.registerPendingDelivery(for: channel))

		#expect(session.deliveryState(forLabel: label) == .pending)

		let echo = try message("@label=\(label);msgid=abc :me!u@h PRIVMSG #chan :hi", on: session)

		#expect(session.resolveLabeledResponse(for: echo))
		#expect(session.deliveryState(forLabel: label) == .none)
	}

	/// `labeled-response`: "If the server has no response to send, it MUST
	/// send `ACK`" — which resolves the label just as an echo would.
	@Test("labeled-response: ACK resolves a label with no other response")
	func acknowledgementResolvesTheLabel() throws {
		let session = labelledSession()
		let channel = try #require(session.findConversationOrCreate("#chan"))
		let label = try #require(session.registerPendingDelivery(for: channel))
		let ack = try message("@label=\(label) ACK", on: session)

		#expect(session.resolveLabeledResponse(for: ack))
		#expect(session.deliveryState(forLabel: label) == .none)
	}

	/// A `FAIL` carrying the label says the command did not happen.
	@Test("labeled-response: a labelled FAIL resolves the label as a failure")
	func labelledFailureResolvesTheLabel() throws {
		let session = labelledSession()
		let channel = try #require(session.findConversationOrCreate("#chan"))
		let label = try #require(session.registerPendingDelivery(for: channel))
		let failure = try message(
			"@label=\(label) FAIL PRIVMSG ACCOUNT_REQUIRED_TO_MESSAGE :log in first",
			on: session
		)

		#expect(session.resolveLabeledResponse(for: failure))
		#expect(session.deliveryState(forLabel: label) == .none)
	}

	/// A label the session never issued, or has already resolved, must not
	/// consume the message: the dispatcher drops whatever this claims.
	@Test("labeled-response: an unknown label does not consume the message")
	func unknownLabelsDoNotConsumeTheMessage() throws {
		let session = labelledSession()
		let stray = try message("@label=g99 :me!u@h PRIVMSG #chan :hi", on: session)

		#expect(session.resolveLabeledResponse(for: stray) == false)
	}

	/// `labeled-response`: a response that is more than one message comes in a
	/// batch whose opening `BATCH` carries the label, so every message in the
	/// batch belongs to that label.
	@Test("labeled-response: a labelled batch resolves when it closes")
	func labelledBatchResolvesWhenItCloses() throws {
		let session = labelledSession()

		session.enableCapability(.batch)

		let channel = try #require(session.findConversationOrCreate("#chan"))
		let label = try #require(session.registerPendingDelivery(for: channel))
		let opening = try message("@label=\(label) :irc.example.net BATCH +ref labeled-response", on: session)

		#expect(session.resolveLabeledResponse(for: opening) == false)
		session.receiveBatch(opening)
		#expect(session.deliveryState(forLabel: label) == .pending)

		let closing = try message(":irc.example.net BATCH -ref", on: session)

		#expect(session.resolveLabeledResponse(for: closing) == false)
		session.receiveBatch(closing)
		#expect(session.deliveryState(forLabel: label) == .none)
	}

	/// A label can only go out on a `label` tag, so `labeled-response` needs
	/// `message-tags`; without either there is nothing to correlate with.
	@Test("labeled-response: no label is issued without message-tags")
	func noLabelWithoutTheCapabilities() throws {
		let bare = TestServerSession(configDictionary: ["nickname": "me"])
		let bareChannel = try #require(bare.findConversationOrCreate("#chan"))

		#expect(bare.registerPendingDelivery(for: bareChannel) == nil)

		let untagged = TestServerSession(configDictionary: ["nickname": "me"])

		untagged.enableCapability(.labeledResponse)

		let untaggedChannel = try #require(untagged.findConversationOrCreate("#chan"))

		#expect(untagged.registerPendingDelivery(for: untaggedChannel) == nil)
	}

	/// `labeled-response` does not need `echo-message`: when the server has no
	/// other response it MUST send `ACK`, which resolves the delivery on its
	/// own. Requiring echo meant a server offering labelled responses without
	/// it had every message go out untracked.
	@Test("labeled-response: labels are issued without echo-message")
	func labelsAreIssuedWithoutEchoMessage() throws {
		let session = TestServerSession(configDictionary: ["nickname": "me"])

		session.enableCapability(.messageTags)
		session.enableCapability(.labeledResponse)

		#expect(session.labeledResponseTrackingEnabled())

		let channel = try #require(session.findConversationOrCreate("#chan"))
		let label = try #require(session.registerPendingDelivery(for: channel))

		#expect(session.deliveryState(forLabel: label) == .pending)

		let ack = try message("@label=\(label) ACK", on: session)

		#expect(session.resolveLabeledResponse(for: ack))
		#expect(session.deliveryState(forLabel: label) == .none)
	}

	/// A `TARGMAX`-grouped message is still one command, so it still carries a
	/// label. The label used to be discarded on this path, which left every
	/// grouped message uncorrelated and its delivery state stuck.
	@Test("labeled-response: a grouped message carries one label")
	func groupedMessagesCarryOneLabel() throws {
		let session = TestServerSession(configDictionary: ["nickname": "me", "username": "me"])

		session.enableCapability(.messageTags)
		session.enableCapability(.labeledResponse)
		session.userHostmask = "me!user@example.org"
		session.supportInfo.processConfigurationData("TARGMAX=PRIVMSG:4")

		let first = try #require(session.findConversationOrCreate("#one"))
		let second = try #require(session.findConversationOrCreate("#two"))

		first.activate()
		second.activate()

		session.sendText(NSAttributedString(string: "hello"), as: .privmsg, toConversations: [first, second])

		let lines = session.sentLines.compactMap { $0 as? String }
		let sent = try #require(lines.first)

		#expect(lines.count == 1)
		#expect(sent.hasPrefix("@label="))
		#expect(sent.hasSuffix(" PRIVMSG #one,#two :hello"))

		let parsed = try #require(LineParser.parsedLine(fromLine: sent))
		let section = try #require(parsed.messageTagSection)
		let label = try #require(MessageTagParser.parsedTags(fromSection: section).tags["label"])

		#expect(session.deliveryState(forLabel: label) == .pending)

		let acknowledgement = try message("@label=\(label) ACK", on: session)

		#expect(session.resolveLabeledResponse(for: acknowledgement))
		#expect(session.deliveryState(forLabel: label) == .none)
	}

	/// Without the capabilities there is no label to put on it, and the
	/// grouped command goes out plain.
	@Test("labeled-response: a grouped message is untagged without the capabilities")
	func groupedMessagesAreUntaggedWithoutTheCapabilities() throws {
		let session = TestServerSession(configDictionary: ["nickname": "me", "username": "me"])

		session.userHostmask = "me!user@example.org"
		session.supportInfo.processConfigurationData("TARGMAX=PRIVMSG:4")

		let first = try #require(session.findConversationOrCreate("#one"))
		let second = try #require(session.findConversationOrCreate("#two"))

		first.activate()
		second.activate()

		session.sendText(NSAttributedString(string: "hello"), as: .privmsg, toConversations: [first, second])

		#expect(session.sentLines.compactMap { $0 as? String } == ["PRIVMSG #one,#two :hello"])
	}

	/// Labels are unique within a connection; reusing one would let a stale
	/// answer resolve a live command.
	@Test("labeled-response: labels are not reused")
	func labelsAreNotReused() throws {
		let session = labelledSession()
		let channel = try #require(session.findConversationOrCreate("#chan"))

		let first = try #require(session.registerPendingDelivery(for: channel))
		let second = try #require(session.registerPendingDelivery(for: channel))

		#expect(first != second)
	}

	/// Which inbound commands can carry a label at all.
	@Test("labeled-response: the responses that resolve a label")
	func responseKindsAreClassified() {
		#expect(LabeledResponsePolicy.responseKind(command: .ack) == .acknowledgement)
		#expect(LabeledResponsePolicy.responseKind(command: .fail) == .failure)
		#expect(LabeledResponsePolicy.responseKind(command: .privmsg) == .echo)
		#expect(LabeledResponsePolicy.responseKind(command: .notice) == .echo)
		#expect(LabeledResponsePolicy.responseKind(command: .tagmsg) == .echo)
		#expect(LabeledResponsePolicy.responseKind(command: .join) == .unrelated)
		// The command is matched however the server spelled its case.
		#expect(LabeledResponsePolicy.responseKind(command: RemoteCommand(wireName: "ack")) == .acknowledgement)
		// A command whose name merely starts the same way is not one of them.
		#expect(LabeledResponsePolicy.responseKind(command: .note) == .unrelated)
		// A numeric reply carries no remote command at all.
		#expect(LabeledResponsePolicy.responseKind(command: nil) == .unrelated)
	}
}
