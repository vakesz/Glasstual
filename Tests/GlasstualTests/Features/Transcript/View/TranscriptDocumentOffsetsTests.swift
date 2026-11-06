// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing

@MainActor
@Suite("Transcript document offsets")
struct TranscriptDocumentOffsetsTests {
	@Test("Retiring the oldest lines keeps every remaining line at its true offset")
	func retiringOldestLinesShiftsOffsets() {
		var document = TranscriptDocument()
		let rows = (0 ..< 5).map { row("line \($0)") }
		document.insert(rows, at: 0, starts: [0, 3, 7, 12, 14], totalLength: 20)

		_ = document.remove(0 ..< 2)

		#expect(document.lineStarts == [0, 5, 7, 13])
		#expect(document.location(ofLineAt: 0) == 0)
		#expect(document.length(ofLineAt: 0) == 5)
		#expect(document.length(ofLineAt: 2) == 6)

		document.insert([row("tail")], at: document.lines.count, starts: [13], totalLength: 4)
		#expect(document.lineStarts == [0, 5, 7, 13, 17])

		_ = document.remove(0 ..< 3)
		#expect(document.lineStarts == [0, 4])
	}

	@Test("A redraw after a trim lands at the shifted location")
	func redrawAfterTrim() {
		var document = TranscriptDocument()
		document.insert([row("a"), row("b"), row("c")], at: 0, starts: [0, 4, 8], totalLength: 12)
		_ = document.remove(0 ..< 1)

		document.noteLineRedrawn(at: 0, newLength: 6)

		#expect(document.lineStarts == [0, 6, 10])
	}

	private func row(_ text: String) -> TranscriptRow {
		TranscriptRow(
			lineNumber: text,
			receivedAt: Date(timeIntervalSince1970: 0),
			nickname: "alice",
			memberType: .normal,
			lineType: .privateMessage,
			command: "PRIVMSG",
			messageIdentifier: "id-\(text)",
			replyToMessageIdentifier: nil,
			deliveryState: .none,
			deliveryFailureReason: nil,
			reactions: [:],
			markers: [],
			body: TranscriptBody(plainText: text, runs: [TranscriptTextRun(text: text)])
		)
	}
}
