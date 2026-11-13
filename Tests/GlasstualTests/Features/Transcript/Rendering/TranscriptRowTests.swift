// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing

@MainActor
@Suite("Transcript row header")
struct TranscriptRowTests {
	private func row(statusMessageTarget: String?) -> TranscriptRow {
		TranscriptRow(
			lineNumber: "line",
			receivedAt: Date(timeIntervalSince1970: 0),
			nickname: "alice",
			memberType: .normal,
			lineType: .privateMessage,
			command: "privmsg",
			messageIdentifier: nil,
			replyToMessageIdentifier: nil,
			deliveryState: .none,
			deliveryFailureReason: nil,
			reactions: [:],
			markers: [],
			body: TranscriptBody(plainText: "ops only", runs: [TranscriptTextRun(text: "ops only")]),
			statusMessageTarget: statusMessageTarget
		)
	}

	@Test("A message only some members received names its target beside the sender")
	func statusMessageHeaderNamesTarget() {
		let plain = row(statusMessageTarget: nil).header(using: .lines).nickname
		let restricted = row(statusMessageTarget: "@#staff").header(using: .lines).nickname

		#expect(restricted.contains(plain))
		#expect(restricted.contains("@#staff"))
		#expect(restricted == ChatLineFormat.statusMessageSender(plain, target: "@#staff"))
	}

	@Test("A message to the whole channel shows the sender alone")
	func publicHeaderIsUnchanged() {
		let header = row(statusMessageTarget: nil).header(using: .lines)

		#expect(header.nickname.contains("alice"))
		#expect(header.nickname.contains("@#") == false)
	}
}
