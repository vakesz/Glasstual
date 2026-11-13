// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing

@MainActor
@Suite("Chat line redaction")
struct ChatLineRedactionTests {
	private func message() -> ChatLine {
		var line = ChatLine()
		line.messageBody = "a secret"
		line.nickname = "alice"
		line.lineType = .privateMessage
		line.messageIdentifier = "msg-1"
		line.reactions = ["👍": ["bob"]]
		line.highlightKeywords = ["secret"]
		line.excludeKeywords = ["other"]
		return line
	}

	@Test("Redaction removes what can be read and keeps what places the line")
	func redactionKeepsTheLinePlace() {
		var line = message()
		let identifier = line.uniqueIdentifier

		line.redact()

		#expect(line.lineType == .redacted)
		#expect(line.messageBody.isEmpty)
		#expect(line.reactions == nil)
		#expect(line.highlightKeywords == nil)
		#expect(line.excludeKeywords == nil)
		#expect(line.nickname == "alice")
		#expect(line.messageIdentifier == "msg-1")
		#expect(line.uniqueIdentifier == identifier)
	}

	@Test("A redacted line is still conversation and survives the stored payload")
	func redactedLineRoundTrips() throws {
		var line = message()
		line.redact()

		let data = try PropertyListEncoder().encode(ChatLineStoredPayload(line: line))
		let decoded = try #require(ChatLine(data: data))

		#expect(decoded.lineType == .redacted)
		#expect(decoded.lineType.isConversation)
		#expect(decoded.messageBody.isEmpty)
		#expect(ChatLine.string(for: .redacted) == "redacted")
	}

	@Test("Redacting twice changes nothing")
	func redactionIsIdempotent() {
		var once = message()
		once.redact()
		var twice = once

		twice.redact()

		#expect(once == twice)
	}
}
