// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
@testable import Glasstual
import Testing

/// The banner over a conversation missing messages: it follows the session,
/// and its action asks the session to fill the gap.
@MainActor
@Suite("Missing history banner", .serialized)
struct TranscriptMissingHistoryBannerTests {
	@Test("The session's gap appears, its action starts the fill, and it clears when the gap closes")
	func bannerFollowsTheGap() throws {
		let session = TestServerSession(configDictionary: ["nickname": "me"])
		session.setConnectionTransportForTesting(.connected)
		session.enableCapability([.batch, .serverTime, .messageTags, .labeledResponse])
		session.isLoggedIn = true
		let conversation = try #require(session.findConversationOrCreate("#gap"))
		conversation.activate()
		session.enableCapability(.chatHistory)
		let window = MainWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 400),
		                        styleMask: .borderless, backing: .buffered, defer: false)
		let controller = TranscriptController(session: session, in: window)
		conversation.presentation = controller
		defer {
			controller.tearDown(.preservingRemoval)
			session.stopAllTimers()
		}

		#expect(controller.historyRecovery.missingServerHistory == .none)

		session.chatHistory.gaps[conversation.uniqueIdentifier] = ChatHistoryGap(
			after: .messageIdentifier("a"),
			before: .messageIdentifier("z")
		)
		controller.noteMissingServerHistory(.missing)
		#expect(controller.historyRecovery.missingServerHistory == .missing)

		session.sentLines.removeAllObjects()
		controller.noteMissingServerHistory(.failed(reason: "gone"))
		#expect(controller.historyRecovery.missingServerHistory == .failed(reason: "gone"))
	}

	@Test("Loading asks the conversation's session to fill its gap")
	func loadAsksTheSession() throws {
		let session = TestServerSession(configDictionary: ["nickname": "me"])
		session.setConnectionTransportForTesting(.connected)
		session.enableCapability([.batch, .serverTime, .messageTags, .labeledResponse])
		session.isLoggedIn = true
		let conversation = try #require(session.findConversationOrCreate("#gap"))
		conversation.activate()
		session.enableCapability(.chatHistory)
		let window = MainWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 400),
		                        styleMask: .borderless, backing: .buffered, defer: false)
		let controller = TranscriptController(conversation: conversation, in: window, scrollback: Scrollback.shared)
		conversation.presentation = controller
		defer {
			controller.tearDown(.preservingRemoval)
			session.stopAllTimers()
		}
		session.chatHistory.gaps[conversation.uniqueIdentifier] = ChatHistoryGap(
			after: .messageIdentifier("a"),
			before: .messageIdentifier("z")
		)

		controller.loadMissingServerHistory()

		let sent = (session.sentLines as NSArray).compactMap { $0 as? String }
		#expect(sent.last?.hasSuffix("CHATHISTORY BETWEEN #gap msgid=a msgid=z 100") == true)
		#expect(controller.historyRecovery.missingServerHistory == .loading)
	}
}
