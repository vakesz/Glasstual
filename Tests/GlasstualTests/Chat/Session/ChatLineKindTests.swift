// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

@testable import Glasstual
import Testing

@Suite("Log line types")
struct ChatLineKindTests {
	@Test("What a person said is conversation")
	func spokenLinesAreConversation() {
		for type in [ChatLineKind.privateMessage, .privateMessageNoHighlight, .action, .actionNoHighlight, .notice] {
			#expect(type.isConversation, "\(type)")
		}
	}

	@Test("What the session narrates on join is not")
	func narratedEventsAreNotConversation() {
		for type in [ChatLineKind.join, .part, .quit, .mode, .topic, .nick, .kick, .debug, .website] {
			#expect(type.isConversation == false, "\(type)")
		}
	}
}
