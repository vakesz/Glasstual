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
 *********************************************************************** */

import Foundation
@testable import Glasstual
import Testing

private func projectionLine(_ body: String) -> LogLine {
	var line = LogLine()
	line.messageBody = body
	line.lineType = .privateMessage
	return line
}

private func projectionResult(for line: LogLine) -> LogLineRenderResult {
	LogLineRenderResult(
		transcriptLine: TranscriptLine(
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
		#expect(replay.results.map(\.lineNumber) == [first.uniqueIdentifier])
		if case .buffered = state.record(projectionResult(for: second)) {} else {
			Issue.record("A loading projection must buffer")
		}

		let pending = state.finishReplay(displaying: Set(replay.results.map(\.lineNumber)))
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

		#expect(state.beginReplay().results.map(\.lineNumber) == [second.uniqueIdentifier])
	}

	/** A delivery receipt can arrive after the line was written to storage, so
	 the state has to hold on to it: the historic row the same replay reads back
	 still says "pending", and the receipt is folded into the row on its way to
	 the transcript. */
	@Test("A delivery update outlives the render it arrived after")
	func deliveryUpdateSurvivesReplay() throws {
		let historic = projectionLine("message")
		var state = TranscriptProjectionState(capacity: 10)
		_ = state.record(projectionResult(for: historic))
		state.updateDelivery(
			lineNumber: historic.uniqueIdentifier,
			state: .delivered,
			messageIdentifier: "server-id",
			reason: nil
		)

		let replay = state.beginReplay()
		#expect(replay.results.map(\.lineNumber) == [historic.uniqueIdentifier])
		let update = try #require(state.deliveryUpdates[historic.uniqueIdentifier])
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
		#expect(replay.results.map(\.lineNumber) == [second.uniqueIdentifier, first.uniqueIdentifier])
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
		#expect(replay.results.map(\.lineNumber) == [second.uniqueIdentifier, third.uniqueIdentifier])
		#expect(state.deliveryUpdates[third.uniqueIdentifier]?.messageIdentifier == "server-id")
		#expect(state.deliveryUpdates[first.uniqueIdentifier] == nil)
	}

	@Test("The default and custom buffer policies match the theme API")
	func bufferPolicy() {
		#expect(LogViewBufferPolicy(preference: 0) == LogViewBufferPolicy(
			preference: UInt.max
		))
		#expect(LogViewBufferPolicy(preference: 0).hardLimit == 1000)
		#expect(LogViewBufferPolicy(preference: 450).hardLimit == 450)
	}
}
