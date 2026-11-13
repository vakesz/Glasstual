// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing

@MainActor
@Suite("Transcript redaction rows")
struct TranscriptDocumentRedactionTests {
	private func row(_ text: String, identifier: String) -> TranscriptRow {
		TranscriptRow(
			lineNumber: text,
			receivedAt: Date(timeIntervalSince1970: 0),
			nickname: "alice",
			memberType: .normal,
			lineType: .privateMessage,
			command: "PRIVMSG",
			messageIdentifier: identifier,
			replyToMessageIdentifier: "parent",
			deliveryState: .delivered,
			deliveryFailureReason: nil,
			reactions: ["👍": ["bob"]],
			markers: [.date("today")],
			body: TranscriptBody(
				plainText: text,
				runs: [TranscriptTextRun(text: text)],
				links: [],
				mentionedNicknames: ["bob"],
				isHighlight: true
			)
		)
	}

	@Test("A redacted row is the placeholder and keeps what places it")
	func rowKeepsItsPlace() {
		var redacted = row("secret", identifier: "msg-1")

		redacted.redact(placeholder: "Message deleted")

		#expect(redacted.lineType == .redacted)
		#expect(redacted.body.plainText == "Message deleted")
		#expect(redacted.body.runs == [TranscriptTextRun(text: "Message deleted", traits: .italic)])
		#expect(redacted.body.isHighlight == false)
		#expect(redacted.body.mentionedNicknames.isEmpty)
		#expect(redacted.reactions.isEmpty)
		#expect(redacted.nickname == "alice")
		#expect(redacted.messageIdentifier == "msg-1")
		#expect(redacted.replyToMessageIdentifier == "parent")
		#expect(redacted.lineNumber == "secret")
		#expect(redacted.markers == [.date("today")])
		#expect(redacted.deliveryState == .delivered)
	}

	@Test("The document redacts only the message named, and not twice")
	func documentRedactsTheNamedMessage() {
		var document = TranscriptDocument()
		document.insert(
			[row("first", identifier: "msg-1"), row("second", identifier: "msg-2")],
			at: 0, starts: [0, 5], totalLength: 11
		)

		#expect(document.redactMessage(messageIdentifier: "msg-2", placeholder: "Message deleted") == [1])
		#expect(document[1].lineType == .redacted)
		#expect(document[0].lineType == .privateMessage)
		#expect(document.highlightedLineCount == 1)
		#expect(document.redactMessage(messageIdentifier: "msg-2", placeholder: "Message deleted").isEmpty)
		#expect(document.redactMessage(messageIdentifier: "unknown", placeholder: "Message deleted").isEmpty)
	}

	@Test("A reaction is not merged into a redacted row, only into one that still has its message")
	func redactedRowTakesNoReactions() {
		var document = TranscriptDocument()
		var bare = row("first", identifier: "msg-1")
		bare.reactions = [:]
		var other = row("second", identifier: "msg-2")
		other.reactions = [:]
		document.insert([bare, other], at: 0, starts: [0, 6], totalLength: 12)
		_ = document.redactMessage(messageIdentifier: "msg-1", placeholder: "Message deleted")

		#expect(document.mergeReactions(["👍": ["carol"]], messageIdentifier: "msg-1").isEmpty)
		#expect(document[0].reactions.isEmpty)
		#expect(document.mergeReactions(["👍": ["carol"]], messageIdentifier: "msg-2") == [1])
		#expect(document[1].reactions == ["👍": ["carol"]])
	}
}
