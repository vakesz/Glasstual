// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing

@Suite("Conversation links")
struct ApplicationConversationLinkTests {
	@Test("A conversation link is a goto link carrying the identifier as its path")
	func linkRoundTrips() throws {
		let identifier = UUID().uuidString
		let link = try #require(ApplicationLink.conversationLink(identifier: identifier))

		guard case let .applicationAction(action, source)? = ApplicationLink.parse(link) else {
			Issue.record("The link did not parse as an application action")
			return
		}
		#expect(action == .goto)
		#expect(source.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")) == identifier)
	}

	@Test("An identifier that cannot sit in a path makes no link", arguments: ["", "a/b"])
	func unusableIdentifiers(_ identifier: String) {
		#expect(ApplicationLink.conversationLink(identifier: identifier) == nil)
	}
}
