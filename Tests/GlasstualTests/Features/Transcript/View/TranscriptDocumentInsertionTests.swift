// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing

@MainActor
@Suite("Transcript document insertion")
struct TranscriptDocumentInsertionTests {
	@Test("Lines put between two others are found by identifier, and so is every line after them")
	func insertionBetweenLinesKeepsEveryIndex() {
		var document = TranscriptDocument()
		document.insert([row("a"), row("b"), row("c")], at: 0, starts: [0, 2, 4], totalLength: 6)

		document.insert([row("x"), row("y")], at: 1, starts: [2, 5], totalLength: 7)

		#expect(document.lines.map(\.lineNumber) == ["a", "x", "y", "b", "c"])
		#expect(document.lineStarts == [0, 2, 5, 9, 11, 13])
		for (index, identifier) in ["a", "x", "y", "b", "c"].enumerated() {
			#expect(document.index(ofLine: identifier) == index)
		}
		#expect(document.range(ofLine: "b") == NSRange(location: 9, length: 2))
		#expect(document.range(ofMessage: "id-c") == NSRange(location: 11, length: 2))
	}

	@Test("A message keeps its rows in order when one of them goes in between")
	func messageRowsStayOrdered() throws {
		var document = TranscriptDocument()
		document.insert([row("a", message: "m"), row("c", message: "m")], at: 0, starts: [0, 1], totalLength: 2)

		document.insert([row("b", message: "m")], at: 1, starts: [1], totalLength: 1)

		let first = try #require(document.ordinals(ofMessage: "m")).map { $0 - document.firstLineOrdinal }
		#expect(first == [0, 1, 2])
		#expect(document.mergeReactions(["+1": ["bob"]], messageIdentifier: "m") == [0, 1, 2])
	}

	@Test("The indexes survive a trim and a prepend after an insertion between lines")
	func insertionThenTrimAndPrepend() {
		var document = TranscriptDocument()
		document.insert([row("a"), row("c")], at: 0, starts: [0, 1], totalLength: 2)
		document.insert([row("b")], at: 1, starts: [1], totalLength: 1)

		let retirement = document.remove(0 ..< 1)
		document.insert([row("z")], at: 0, starts: [0], totalLength: 1)

		#expect(retirement.lineNumbers == ["a"])
		#expect(retirement.messageIdentifiers == ["id-a"])
		#expect(document.lines.map(\.lineNumber) == ["z", "b", "c"])
		for (index, identifier) in ["z", "b", "c"].enumerated() {
			#expect(document.index(ofLine: identifier) == index)
		}
		#expect(document.contains(identifier: "a") == false)
	}

	private func row(_ text: String, message: String? = nil) -> TranscriptRow {
		TranscriptRow(
			lineNumber: text,
			receivedAt: Date(timeIntervalSince1970: 0),
			nickname: "alice",
			memberType: .normal,
			lineType: .privateMessage,
			command: "PRIVMSG",
			messageIdentifier: message ?? "id-\(text)",
			replyToMessageIdentifier: nil,
			deliveryState: .none,
			deliveryFailureReason: nil,
			reactions: [:],
			markers: [],
			body: TranscriptBody(plainText: text, runs: [TranscriptTextRun(text: text)])
		)
	}
}
