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
			timestamp: "",
			nickname: nil,
			formattedNickname: "",
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

	@Test("An in-memory delivery update wins over the historic copy")
	func deliveryUpdateSurvivesReplayMerge() throws {
		let historic = projectionLine("message")
		var state = TranscriptProjectionState(capacity: 10)
		_ = state.record(historic, rendered: projectionResult(for: historic))
		state.updateDelivery(
			lineNumber: historic.uniqueIdentifier,
			state: .delivered,
			messageIdentifier: "server-id",
			reason: nil
		)

		let merged = TranscriptProjectionState.merging(
			historic: [historic],
			replay: state.beginReplay().lines
		)
		let line = try #require(merged.first)
		#expect(line.deliveryState == .delivered)
		#expect(line.messageIdentifier == "server-id")
	}

	@Test("The default and custom buffer policies match the theme API")
	func bufferPolicy() {
		#expect(LogViewBufferPolicy(preference: 0) == LogViewBufferPolicy(
			preference: UInt.max
		))
		#expect(LogViewBufferPolicy(preference: 0).softLimit == 200)
		#expect(LogViewBufferPolicy(preference: 0).hardLimit == 1000)
		#expect(LogViewBufferPolicy(preference: 450).softLimit == 450)
		#expect(LogViewBufferPolicy(preference: 450).hardLimit == 450)
	}
}
