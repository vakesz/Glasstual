/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\\__|\__,_|\__,_|_|
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
		processesInlineMedia: false,
		pluginMessage: nil
	)
}

@Suite("Transcript projection state")
struct TranscriptProjectionStateTests {
	@Test("Dormant lines replay and lines arriving during replay wait behind them")
	func replayBridgesTheLoadingWindow() {
		let first = projectionLine("first")
		let second = projectionLine("second")
		var state = TranscriptProjectionState(capacity: 10)

		if case .buffered = state.record(first, rendered: projectionResult(for: first)) {} else {
			Issue.record("A dormant projection must buffer")
		}
		let replay = state.beginReplay()
		#expect(replay.lines.map(\.uniqueIdentifier) == [first.uniqueIdentifier])
		if case .buffered = state.record(second, rendered: projectionResult(for: second)) {} else {
			Issue.record("A loading projection must buffer")
		}

		let pending = state.finishReplay(displaying: replay.lineNumbers)
		#expect(pending.map(\.lineNumber) == [second.uniqueIdentifier])
		#expect(state.phase == .active)
	}

	@Test("The native tail stays at the configured hard limit")
	func tailIsBounded() {
		let first = projectionLine("first")
		let second = projectionLine("second")
		var state = TranscriptProjectionState(capacity: 1)

		_ = state.record(first, rendered: projectionResult(for: first))
		_ = state.record(second, rendered: projectionResult(for: second))

		#expect(state.beginReplay().lines.map(\.uniqueIdentifier) == [second.uniqueIdentifier])
	}

	/** A delivery receipt can arrive after the line was written to storage, so
	 the copy the tail replays has to be the one carrying it: the historic row
	 the same replay reads back still says "pending". */
	@Test("A delivery update reaches the copy the tail replays")
	func deliveryUpdateSurvivesReplay() throws {
		let historic = projectionLine("message")
		var state = TranscriptProjectionState(capacity: 10)
		_ = state.record(historic, rendered: projectionResult(for: historic))
		state.updateDelivery(
			lineNumber: historic.uniqueIdentifier,
			state: .delivered,
			messageIdentifier: "server-id",
			reason: nil
		)

		let replay = state.beginReplay()
		let line = try #require(replay.lines.first)
		#expect(line.deliveryState == .delivered)
		#expect(line.messageIdentifier == "server-id")
		#expect(state.deliveryUpdates[historic.uniqueIdentifier]?.state == .delivered)
	}

	/** Reprinting a line the tail already holds moves it to the end rather than
	 leaving two copies, and the side table that finds it has to move with it —
	 a stale index would hand a later update the wrong row. */
	@Test("A reprinted line moves to the end and stays findable")
	func reprintingMovesTheLineToTheEnd() {
		let first = projectionLine("first")
		let second = projectionLine("second")
		var state = TranscriptProjectionState(capacity: 10)

		_ = state.record(first, rendered: projectionResult(for: first))
		_ = state.record(second, rendered: projectionResult(for: second))
		_ = state.record(first, rendered: projectionResult(for: first))
		state.updateDelivery(
			lineNumber: second.uniqueIdentifier,
			state: .failed,
			messageIdentifier: nil,
			reason: "rejected"
		)

		let replay = state.beginReplay()
		#expect(replay.lines.map(\.uniqueIdentifier) == [second.uniqueIdentifier, first.uniqueIdentifier])
		#expect(replay.lines.first?.deliveryState == .failed)
	}

	/// Trimming the head shifts every remaining line, so the side table has to
	/// keep pointing at the rows it names.
	@Test("A line that survives trimming is still found by a later update")
	func trimmingKeepsTheSurvivingLineFindable() {
		let first = projectionLine("first")
		let second = projectionLine("second")
		let third = projectionLine("third")
		var state = TranscriptProjectionState(capacity: 2)

		_ = state.record(first, rendered: projectionResult(for: first))
		_ = state.record(second, rendered: projectionResult(for: second))
		_ = state.record(third, rendered: projectionResult(for: third))
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
		#expect(replay.lines.map(\.uniqueIdentifier) == [second.uniqueIdentifier, third.uniqueIdentifier])
		#expect(replay.lines.last?.messageIdentifier == "server-id")
		#expect(replay.lines.contains { $0.messageIdentifier == "dropped" } == false)
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
