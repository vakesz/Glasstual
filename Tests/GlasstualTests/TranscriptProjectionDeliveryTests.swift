// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing

/// Delivery receipts arrive long after the line they answer, and a buffered
/// transcript drops its oldest lines as it goes. A receipt for a line that is
/// gone has nowhere to land, and keeping one would grow the state for the life
/// of the session.
@Suite("Transcript projection delivery updates")
struct TranscriptProjectionDeliveryTests {
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
		_ = state.record(rendered(lines[0]))
		state.updateDelivery(
			lineNumber: lines[0].uniqueIdentifier, state: .delivered, messageIdentifier: nil, reason: nil
		)
		#expect(state.deliveryUpdates[lines[0].uniqueIdentifier]?.state == .delivered)

		for line in lines.dropFirst() {
			_ = state.record(rendered(line))
		}
		_ = state.record(rendered(lines[1]))
		#expect(state.deliveryUpdates[lines[0].uniqueIdentifier] == nil)

		/* The ack the server sends after the line has scrolled out of the buffer
		 is the one that used to be kept for good. */
		state.updateDelivery(
			lineNumber: lines[0].uniqueIdentifier, state: .delivered, messageIdentifier: nil, reason: nil
		)
		#expect(state.deliveryUpdates[lines[0].uniqueIdentifier] == nil)
	}

	private func rendered(_ line: LogLine) -> TranscriptRenderResult {
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
}
