// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing

private func projectionLine(_ body: String) -> ChatLine {
	var line = ChatLine()
	line.messageBody = body
	line.lineType = .privateMessage
	return line
}

private func projectionResult(for line: ChatLine) -> TranscriptRenderResult {
	TranscriptRenderResult(
		transcriptLine: TranscriptRow(
			lineNumber: line.uniqueIdentifier,
			receivedAt: line.receivedAt,
			nickname: nil,
			memberType: .normal,
			lineType: line.lineType,
			command: line.command,
			messageIdentifier: nil,
			replyToMessageIdentifier: nil,
			deliveryState: .none,
			deliveryFailureReason: nil,
			reactions: [:],
			markers: [],
			body: TranscriptBody(plainText: line.messageBody)
		),
		fromCurrentSession: line.fromCurrentSession,
		processesInlineMedia: false
	)
}

@Suite("Transcript projection state")
struct TranscriptProjectionStateTests {
	@Test("Dormant lines replay and lines arriving during replay wait behind them")
	func replayBridgesTheLoadingWindow() {
		let first = projectionLine("first")
		let second = projectionLine("second")
		var state = TranscriptProjectionState(capacity: 10)

		if case .buffered = state.record(projectionResult(for: first)) {} else {
			Issue.record("A dormant projection must buffer")
		}
		let replay = state.beginReplay()
		#expect(replay.map(\.lineNumber) == [first.uniqueIdentifier])
		if case .buffered = state.record(projectionResult(for: second)) {} else {
			Issue.record("A loading projection must buffer")
		}

		let pending = state.finishReplay(displaying: Set(replay.map(\.lineNumber)))
		#expect(pending.map(\.lineNumber) == [second.uniqueIdentifier])
		#expect(state.phase == .active)
	}

	@Test("The native tail stays at the configured hard limit")
	func tailIsBounded() {
		let first = projectionLine("first")
		let second = projectionLine("second")
		var state = TranscriptProjectionState(capacity: 1)

		_ = state.record(projectionResult(for: first))
		_ = state.record(projectionResult(for: second))

		#expect(state.beginReplay().map(\.lineNumber) == [second.uniqueIdentifier])
	}

	@Test("The document owns active rows and supplies only a temporary replay snapshot")
	func activeRowsAreNotRetainedTwice() {
		let first = projectionResult(for: projectionLine("first"))
		let second = projectionResult(for: projectionLine("second"))
		var state = TranscriptProjectionState(capacity: 10)
		_ = state.record(first)
		_ = state.beginReplay()
		_ = state.finishReplay(displaying: [first.lineNumber])

		#expect(state.lineCount == 0)
		#expect(!state.containsLine(withIdentifier: first.lineNumber))
		if case .append = state.record(second) {} else {
			Issue.record("An active print must go straight to the document")
		}
		#expect(state.lineCount == 0)

		let replay = state.beginReplay(displaying: [first.transcriptLine, second.transcriptLine])
		#expect(replay.map(\.lineNumber) == [first.lineNumber, second.lineNumber])
		_ = state.finishReplay(displaying: Set(replay.map(\.lineNumber)))
		#expect(state.lineCount == 0)
	}

	@Test("An active receipt is kept until the document applies it")
	func activeReceiptIsTemporary() throws {
		let line = projectionResult(for: projectionLine("pending"))
		var state = TranscriptProjectionState(capacity: 10)
		_ = state.record(line)
		_ = state.beginReplay()
		_ = state.finishReplay(displaying: [line.lineNumber])

		let received = state.updateDelivery(
			lineNumber: line.lineNumber, state: .delivered,
			messageIdentifier: "server-id", reason: nil, isDisplayed: true
		)
		let update = try #require(received)
		#expect(state.containsMessage(withIdentifier: "server-id"))
		state.deliveryWasApplied(update)
		#expect(state.deliveryUpdates.isEmpty)
		#expect(!state.containsMessage(withIdentifier: "server-id"))
		#expect(state.lineCount == 0)

		_ = state.updateDelivery(
			lineNumber: line.lineNumber, state: .failed,
			messageIdentifier: "another-id", reason: "rejected", isDisplayed: true
		)
		state.retireDisplayedLines([line.lineNumber])
		#expect(state.deliveryUpdates.isEmpty)
		#expect(!state.containsMessage(withIdentifier: "another-id"))
	}

	@Test("A later delivery state keeps the message identifier from its acknowledgement")
	func deliveryStateKeepsAcknowledgedIdentifier() throws {
		let line = projectionResult(for: projectionLine("pending"))
		var state = TranscriptProjectionState(capacity: 10)
		_ = state.record(line)
		_ = state.updateDelivery(
			lineNumber: line.lineNumber, state: .delivered,
			messageIdentifier: "server-id", reason: nil
		)
		let received = state.updateDelivery(
			lineNumber: line.lineNumber, state: .failed,
			messageIdentifier: nil, reason: "later failure"
		)
		let failed = try #require(received)
		#expect(failed.messageIdentifier == "server-id")
		#expect(state.containsMessage(withIdentifier: "server-id"))
	}

	/** A delivery receipt can arrive after the line was written to storage, so
	 the state has to hold on to it: the stored row the same replay reads back
	 still says "pending", and the receipt is folded into the row on its way to
	 the transcript. */
	@Test("A delivery update outlives the render it arrived after")
	func deliveryUpdateSurvivesReplay() throws {
		let storedLine = projectionLine("message")
		var state = TranscriptProjectionState(capacity: 10)
		_ = state.record(projectionResult(for: storedLine))
		state.updateDelivery(
			lineNumber: storedLine.uniqueIdentifier,
			state: .delivered,
			messageIdentifier: "server-id",
			reason: nil
		)

		let replay = state.beginReplay()
		#expect(replay.map(\.lineNumber) == [storedLine.uniqueIdentifier])
		let update = try #require(state.deliveryUpdates[storedLine.uniqueIdentifier])
		#expect(update.state == .delivered)
		#expect(update.messageIdentifier == "server-id")
	}

	/** The tail keeps one row per line: reprinting a line it already holds
	 moves that row to the end instead of adding a second, and a later delivery
	 update still reaches it. */
	@Test("A reprinted line moves to the end and stays findable")
	func reprintingMovesTheLineToTheEnd() {
		let first = projectionLine("first")
		let second = projectionLine("second")
		var state = TranscriptProjectionState(capacity: 10)

		_ = state.record(projectionResult(for: first))
		_ = state.record(projectionResult(for: second))
		_ = state.record(projectionResult(for: first))
		state.updateDelivery(
			lineNumber: second.uniqueIdentifier,
			state: .failed,
			messageIdentifier: nil,
			reason: "rejected"
		)

		let replay = state.beginReplay()
		#expect(replay.map(\.lineNumber) == [second.uniqueIdentifier, first.uniqueIdentifier])
		#expect(state.deliveryUpdates[second.uniqueIdentifier]?.state == .failed)
	}

	/// Trimming drops the oldest rows, so a later delivery update reaches a
	/// surviving line and finds nothing for one the trim dropped.
	@Test("A line that survives trimming is still found by a later update")
	func trimmingKeepsTheSurvivingLineFindable() {
		let first = projectionLine("first")
		let second = projectionLine("second")
		let third = projectionLine("third")
		var state = TranscriptProjectionState(capacity: 2)

		_ = state.record(projectionResult(for: first))
		_ = state.record(projectionResult(for: second))
		_ = state.record(projectionResult(for: third))
		state.updateDelivery(
			lineNumber: third.uniqueIdentifier,
			state: .delivered,
			messageIdentifier: "server-id",
			reason: nil
		)
		state.updateDelivery(
			lineNumber: first.uniqueIdentifier,
			state: .delivered,
			messageIdentifier: "dropped",
			reason: nil
		)

		let replay = state.beginReplay()
		#expect(replay.map(\.lineNumber) == [second.uniqueIdentifier, third.uniqueIdentifier])
		#expect(state.deliveryUpdates[third.uniqueIdentifier]?.messageIdentifier == "server-id")
		#expect(state.deliveryUpdates[first.uniqueIdentifier] == nil)
	}

	@Test("The default and custom buffer policies match the theme API")
	func bufferPolicy() {
		#expect(TranscriptBufferLimits(setting: 0) == TranscriptBufferLimits(
			setting: UInt.max
		))
		#expect(TranscriptBufferLimits(setting: 0).hardLimit == 1000)
		#expect(TranscriptBufferLimits(setting: 450).hardLimit == 450)
	}
}
