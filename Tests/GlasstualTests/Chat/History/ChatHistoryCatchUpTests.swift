// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing

@Suite("Chat history catch-up and gap fill")
struct ChatHistoryCatchUpTests {
	private let date = Date(timeIntervalSince1970: 1_793_260_800)

	@Test("With nothing known the latest page is asked for")
	func nothingKnownAsksLatest() {
		var catchUp = ChatHistoryCatchUp(target: "#c", known: nil, limit: 100)
		#expect(catchUp.start() == .send(.latest(target: "#c", after: .unbounded, limit: 100)))
		#expect(catchUp.receivedPage(count: 100, first: nil, last: .messageIdentifier("x")) == .finished)
	}

	@Test("A message identifier pages forward from itself; a timestamp from five seconds earlier")
	func knownReferences() {
		var byIdentifier = ChatHistoryCatchUp(target: "#c", known: .messageIdentifier("abc"), limit: 100)
		#expect(byIdentifier.start() == .send(.after(target: "#c", .messageIdentifier("abc"), limit: 100)))

		var byTime = ChatHistoryCatchUp(target: "#c", known: .timestamp(date), limit: 100)
		#expect(byTime.start() == .send(.after(target: "#c", .timestamp(date.addingTimeInterval(-5)), limit: 100)))
	}

	@Test("A full page asks for the next one from its newest line; a short page finishes")
	func fullAndShortPages() {
		var catchUp = ChatHistoryCatchUp(target: "#c", known: .messageIdentifier("a"), limit: 2)
		_ = catchUp.start()
		#expect(catchUp.receivedPage(count: 2, first: .messageIdentifier("b"), last: .messageIdentifier("c"))
			== .send(.after(target: "#c", .messageIdentifier("c"), limit: 2)))
		#expect(catchUp.receivedPage(count: 1, first: .messageIdentifier("d"), last: .messageIdentifier("d")) == .finished)
	}

	@Test("After the page cap the live end is fetched and what lies between becomes a gap")
	func capRecordsAGap() {
		var catchUp = ChatHistoryCatchUp(target: "#c", known: .messageIdentifier("a"), limit: 1, maximumPages: 2)
		_ = catchUp.start()
		#expect(catchUp.receivedPage(count: 1, first: .messageIdentifier("b"), last: .messageIdentifier("b"))
			== .send(.after(target: "#c", .messageIdentifier("b"), limit: 1)))
		#expect(catchUp.receivedPage(count: 1, first: .messageIdentifier("c"), last: .messageIdentifier("c"))
			== .send(.latest(target: "#c", after: .unbounded, limit: 1)))
		#expect(catchUp.receivedPage(count: 1, first: .messageIdentifier("z"), last: .messageIdentifier("z"))
			== .finishedWithGap(ChatHistoryGap(after: .messageIdentifier("c"), before: .messageIdentifier("z"))))
	}

	@Test("A gap fill pages BETWEEN its bounds and stops on a short page")
	func gapFillPaging() {
		let gap = ChatHistoryGap(after: .messageIdentifier("a"), before: .messageIdentifier("z"))
		var fill = ChatHistoryGapFill(target: "#c", gap: gap, limit: 2)
		#expect(fill.start() == .send(.between(target: "#c", .messageIdentifier("a"), .messageIdentifier("z"), limit: 2)))
		#expect(fill.receivedPage(count: 2, last: .messageIdentifier("m"))
			== .send(.between(target: "#c", .messageIdentifier("m"), .messageIdentifier("z"), limit: 2)))
		#expect(fill.receivedPage(count: 1, last: .messageIdentifier("n")) == .finished)
	}

	@Test("A gap fill that reaches its cap hands back what is left")
	func gapFillCap() {
		let gap = ChatHistoryGap(after: .messageIdentifier("a"), before: .messageIdentifier("z"))
		var fill = ChatHistoryGapFill(target: "#c", gap: gap, limit: 1, maximumPages: 1)
		_ = fill.start()
		#expect(fill.receivedPage(count: 1, last: .messageIdentifier("b"))
			== .finishedWithGap(ChatHistoryGap(after: .messageIdentifier("b"), before: .messageIdentifier("z"))))
	}
}

@MainActor
private final class MissingHistoryRecordingPresentation: ChatItemPresenting {
	private(set) var states: [MissingServerHistoryState] = []
	private(set) var archived: [ChatLine] = []
	private(set) var printed: [ChatLine] = []
	var newestIdentifier: String?

	let presentationIdentifier = "missing-history-recording-presentation"

	func print(_ line: ChatLine, completionBlock _: PrintedLineCompletion?) {
		printed.append(line)
	}

	func lastPrintedLine() -> ChatLine? {
		nil
	}

	func newestMessageIdentifier(sentBy _: (String) -> Bool) -> String? {
		newestIdentifier
	}

	nonisolated func setTopic(_: String?) {} // nonisolated: pure
	func mark() {}
	func mark(at _: Date) {}
	func noteReaction(_: String, fromNickname _: String, toMessageIdentifier _: String) {}
	func updateDeliveryState(
		forLineNumber _: String,
		state _: ChatLineDeliveryState,
		messageIdentifier _: String?,
		reason _: String?
	) {}
	func prependEarlierChatLines(_: [ChatLine]) {}
	func archiveRecoveredChatLines(_ lines: [ChatLine]) {
		archived += lines
	}

	func noteMissingServerHistory(_ state: MissingServerHistoryState) {
		states.append(state)
	}

	func tearDown(_: ChatItemTeardown) {}
}

/// Catch-up on join, the gap it may leave, and filling that gap.
@MainActor
@Suite("Chat history catch-up on a session")
struct ServerSessionChatHistoryCatchUpTests {
	private struct Fixture {
		let session: TestServerSession
		let channel: Conversation
		let presentation: MissingHistoryRecordingPresentation
	}

	private func makeFixture(limit: UInt = 2) throws -> Fixture {
		let session = TestServerSession()
		session.enableCapability(.batch)
		session.enableCapability(.serverTime)
		session.enableCapability(.messageTags)
		session.enableCapability(.labeledResponse)
		session.supportInfo.processConfigurationData("CHATHISTORY=\(limit)")
		session.isLoggedIn = true
		session.forwardsProcessedMessages = true
		let channel = try #require(session.findConversationOrCreate("#chat"))
		// Joined before history is on, so joining asks for nothing yet.
		channel.activate()
		session.enableCapability(.chatHistory)
		let presentation = MissingHistoryRecordingPresentation()
		presentation.newestIdentifier = "known"
		channel.presentation = presentation
		return Fixture(session: session, channel: channel, presentation: presentation)
	}

	private func sent(by session: TestServerSession) -> [String] {
		(session.sentLines as NSArray).compactMap { $0 as? String }
	}

	private func label(of line: String) throws -> String {
		try #require(line.split(separator: " ").first.map { String($0.dropFirst("@label=".count)) })
	}

	private func feed(_ lines: [String], to session: TestServerSession) throws {
		for line in lines {
			let message = try #require(Message(line: line, on: session))
			if session.filterBatchCommandIncomingData(message) {
				continue
			}
			if message.command == "BATCH" {
				session.receiveBatch(message)
			} else {
				session.processIncomingMessage(message)
			}
		}
	}

	/// A labelled page of `identifiers`, as the server answers one.
	private func page(_ identifiers: [String], label: String, token: String) -> [String] {
		[":irc.example.net BATCH +\(token) chathistory #chat"].map { "@label=\(label) " + $0 }
			+ identifiers.map { "@batch=\(token);msgid=\($0);time=2026-11-01T00:00:00.000Z :a!u@h PRIVMSG #chat :\($0)" }
			+ [":irc.example.net BATCH -\(token)"]
	}

	@Test("Joining asks AFTER the newest known message, labelled, and a full page asks for the next")
	func catchUpPagesForward() throws {
		let fixture = try makeFixture()
		let (session, channel, presentation) = (fixture.session, fixture.channel, fixture.presentation)
		defer { withExtendedLifetime(presentation) {} }
		defer { session.stopAllTimers() }

		session.requestChatHistory(for: channel)
		let first = try #require(sent(by: session).last)
		#expect(first.hasPrefix("@label=paging-"))
		#expect(first.hasSuffix("CHATHISTORY AFTER #chat msgid=known 2"))

		try feed(page(["m1", "m2"], label: label(of: first), token: "p1"), to: session)
		let second = try #require(sent(by: session).last)
		#expect(second.hasSuffix("CHATHISTORY AFTER #chat msgid=m2 2"))

		try feed(page(["m3"], label: label(of: second), token: "p2"), to: session)
		#expect(session.chatHistory.paging.isEmpty)
		#expect(session.chatHistory.gaps.isEmpty)
	}

	@Test("A scroll-back page is refused while a catch-up runs")
	func scrollBackWaits() throws {
		let fixture = try makeFixture()
		let (session, channel, presentation) = (fixture.session, fixture.channel, fixture.presentation)
		defer { withExtendedLifetime(presentation) {} }
		defer { session.stopAllTimers() }

		session.requestChatHistory(for: channel)
		let request = ServerHistoryRequest(id: UUID(), before: Date(), oldestLineNumber: nil)

		#expect(session.requestServerHistory(request, in: channel) == false)
	}

	@Test("A FAIL ends the catch-up and leaves no gap")
	func failureEndsCatchUp() throws {
		let fixture = try makeFixture()
		let (session, channel, presentation) = (fixture.session, fixture.channel, fixture.presentation)
		defer { withExtendedLifetime(presentation) {} }
		defer { session.stopAllTimers() }

		session.requestChatHistory(for: channel)
		let request = try label(of: #require(sent(by: session).last))
		try feed(["@label=\(request) :irc.example.net FAIL CHATHISTORY MESSAGE_ERROR AFTER #chat :Nope"], to: session)

		#expect(session.chatHistory.paging.isEmpty)
		#expect(session.chatHistory.gaps.isEmpty)
	}

	@Test("Reaching the page cap records a gap, and filling it archives the lines instead of drawing them")
	func gapIsRecordedAndFilled() throws {
		let fixture = try makeFixture(limit: 1)
		let (session, channel, presentation) = (fixture.session, fixture.channel, fixture.presentation)
		defer { session.stopAllTimers() }

		session.requestChatHistory(for: channel)
		for index in 1 ... ChatHistoryPolicy.maximumPagingPages {
			try feed(page(["m\(index)"], label: label(of: #require(sent(by: session).last)), token: "p\(index)"), to: session)
		}
		let latest = try #require(sent(by: session).last)
		#expect(latest.hasSuffix("CHATHISTORY LATEST #chat * 1"))
		try feed(page(["live"], label: label(of: latest), token: "live"), to: session)

		#expect(session.chatHistory.gaps[channel.uniqueIdentifier]
			== ChatHistoryGap(after: .messageIdentifier("m10"), before: .messageIdentifier("live")))
		#expect(presentation.states.last == .missing)

		let printedBeforeFill = presentation.printed.count
		#expect(session.fillChatHistoryGap(in: channel))
		let fill = try #require(sent(by: session).last)
		#expect(fill.hasSuffix("CHATHISTORY BETWEEN #chat msgid=m10 msgid=live 1"))
		#expect(presentation.states.last == .loading)

		try feed([
			"@label=\(label(of: fill)) :irc.example.net BATCH +f chathistory #chat",
			":irc.example.net BATCH -f",
		], to: session)

		#expect(session.chatHistory.gaps.isEmpty)
		#expect(presentation.states.last == MissingServerHistoryState.none)
		#expect(presentation.printed.count == printedBeforeFill)
	}

	@Test("A gap-fill page goes to the archive, not to the end of the transcript")
	func gapFillLinesAreArchived() throws {
		let fixture = try makeFixture(limit: 5)
		let (session, channel, presentation) = (fixture.session, fixture.channel, fixture.presentation)
		defer { session.stopAllTimers() }
		session.chatHistory.gaps[channel.uniqueIdentifier] = ChatHistoryGap(after: .messageIdentifier("a"), before: .messageIdentifier("z"))
		// Lines take the real printing path, which is where a fill collects them.
		session.linePrintObserver = nil

		#expect(session.fillChatHistoryGap(in: channel))
		let fill = try #require(sent(by: session).last)
		try feed(page(["g1", "g2"], label: label(of: fill), token: "g"), to: session)

		#expect(presentation.archived.map(\.messageIdentifier) == ["g1", "g2"])
		#expect(presentation.printed.isEmpty)
		#expect(session.chatHistory.gaps.isEmpty)
	}

	@Test("/chathistory fill with nothing missing says so")
	func fillWithNothingMissing() throws {
		let fixture = try makeFixture()
		let (session, presentation) = (fixture.session, fixture.presentation)
		defer { withExtendedLifetime(presentation) {} }

		session.sendCommand("chathistory fill", completeTarget: true, target: "#chat")

		let printed = (session.printedLines as NSArray).compactMap { ($0 as? [String: Any])?["messageBody"] as? String }
		#expect(printed.last == String(localized: .ChatHistory.chatHistoryNothingMissing("#chat")))
	}
}
