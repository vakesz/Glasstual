// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

@testable import Glasstual
import Testing

@Suite("Log line types")
struct ChatLineKindTests {
	@Test(
		"What a person said is conversation",
		arguments: [ChatLineKind.privateMessage, .privateMessageNoHighlight, .action, .actionNoHighlight, .notice]
	)
	func spokenLinesAreConversation(_ type: ChatLineKind) {
		#expect(type.isConversation, "\(type)")
	}

	@Test(
		"What the session narrates on join is not",
		arguments: [ChatLineKind.join, .part, .quit, .mode, .topic, .nick, .kick, .debug, .website]
	)
	func narratedEventsAreNotConversation(_ type: ChatLineKind) {
		#expect(type.isConversation == false, "\(type)")
	}
}
