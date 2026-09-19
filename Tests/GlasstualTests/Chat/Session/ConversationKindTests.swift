// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

@testable import Glasstual
import Testing

@MainActor
@Suite("Conversation kinds and statuses")
struct ConversationKindTests {
	@Test("Conversation kind and status raw values are the ones stored configs carry")
	func conversationKindAndStatusRawValuesRemainStable() {
		#expect(ConversationKind.channel.rawValue == 0)
		#expect(ConversationKind.direct.rawValue == 1)
		#expect(ConversationKind.console.rawValue == 2)
		#expect(ConversationKind.directChat.rawValue == 3)

		#expect(ConversationStatus.parted.rawValue == 0)
		#expect(ConversationStatus.joining.rawValue == 1)
		#expect(ConversationStatus.joined.rawValue == 2)
		#expect(ConversationStatus.terminated.rawValue == 3)
	}
}
