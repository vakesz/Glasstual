/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import Foundation
@testable import Glasstual
import Testing

/// Delivery receipts arrive long after the line they answer, and a buffered
/// transcript drops its oldest lines as it goes. A receipt for a line that is
/// gone has nowhere to land, and keeping one would grow the state for the life
/// of the session.
@Suite("Transcript projection delivery updates")
struct TranscriptProjectionDeliveryTests {
	@Test("A receipt for a line the buffer never held is not retained")
	func receiptForAnUnknownLineIsDropped() {
		var state = TranscriptProjectionState(capacity: 2)
		state.updateDelivery(lineNumber: "never-printed", state: .delivered, messageIdentifier: nil, reason: nil)
		#expect(state.deliveryUpdates.isEmpty)
	}

	@Test("A receipt is forgotten with the line it belongs to, and a later one for it is refused")
	func receiptsAreTrimmedWithTheirLinesAndNotRecreated() {
		var state = TranscriptProjectionState(capacity: 2)
		var lines: [LogLine] = []
		for index in 0 ..< 3 {
			var line = LogLine()
			line.messageBody = "body \(index)"
			line.lineType = .privateMessage
			lines.append(line)
		}
		_ = state.record(lines[0], rendered: rendered(lines[0]))
		state.updateDelivery(
			lineNumber: lines[0].uniqueIdentifier, state: .delivered, messageIdentifier: nil, reason: nil
		)
		#expect(state.deliveryUpdates[lines[0].uniqueIdentifier]?.state == .delivered)

		for line in lines.dropFirst() {
			_ = state.record(line, rendered: rendered(line))
		}
		_ = state.record(lines[1], rendered: rendered(lines[1]))
		#expect(state.deliveryUpdates[lines[0].uniqueIdentifier] == nil)

		/* The ack the server sends after the line has scrolled out of the buffer
		 is the one that used to be kept for good. */
		state.updateDelivery(
			lineNumber: lines[0].uniqueIdentifier, state: .delivered, messageIdentifier: nil, reason: nil
		)
		#expect(state.deliveryUpdates[lines[0].uniqueIdentifier] == nil)
	}

	private func rendered(_ line: LogLine) -> LogLineRenderResult {
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
}
