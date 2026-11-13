// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing

@Suite("Typing sender")
@MainActor
struct TypingSenderTests {
	private enum DestinationChange: CaseIterable {
		case removed, parted, renamed, notificationsDisabled, quitting, disconnecting
	}

	@Test("A pending typing pause cannot outlive its destination", arguments: DestinationChange.allCases)
	private func pendingPauseRejectsChangedDestination(_ change: DestinationChange) throws {
		let session = TestServerSession()
		session.setConnectionTransportForTesting(.connected)
		session.markAsLoggedIn()
		session.enableCapability(.messageTags)
		session.environment.settings.sendTypingNotifications = true
		let conversation = try #require(session.findConversationOrCreate("alice", isDirect: true))
		conversation.activate()
		defer { session.cancelPendingSessionTasks() }
		let start = Date()
		session.typingSender.noteText("hello", in: conversation, at: start)
		try #require(session.sentLines.compactMap { $0 as? String } == ["@+typing=active TAGMSG alice"])

		switch change {
		case .removed: session.remove(conversation)
		case .parted: conversation.deactivate()
		case .renamed: conversation.name = "bob"
		case .notificationsDisabled: session.environment.settings.sendTypingNotifications = false
		case .quitting: session.connectionState.beginQuit()
		case .disconnecting: session.connectionState.beginDisconnect()
		}
		session.sentLines.removeAllObjects()
		session.typingSender.pause(in: conversation, at: start.addingTimeInterval(5))
		session.typingSender.finish(in: conversation, at: start.addingTimeInterval(8))

		#expect(session.sentLines.count == 0)
	}

	/// The states go on the wire as the `+typing` tag value, so their spellings
	/// are part of the protocol.
	@Test("Each state keeps the spelling IRCv3 gives it")
	func matchesTheWireSpelling() {
		#expect(TypingState.active.rawValue == "active")
		#expect(TypingState.paused.rawValue == "paused")
		#expect(TypingState.done.rawValue == "done")
		#expect(TypingState(rawValue: "typing") == nil)
	}

	@Test("An active notification is sent again only once the interval is up")
	func rateLimitsTheActiveNotification() throws {
		let session = TestServerSession()
		session.markAsLoggedIn()
		session.enableCapability(.messageTags)
		session.environment.settings.sendTypingNotifications = true
		let conversation = try #require(session.findConversationOrCreate("alice", isDirect: true))
		conversation.activate()
		defer { session.cancelPendingSessionTasks() }
		let now = Date(timeIntervalSince1970: 100)
		session.typingSender.noteText("hello", in: conversation, at: now)
		session.typingSender.noteText("hello!", in: conversation, at: now.addingTimeInterval(2.9))
		#expect(session.sentLines.count == 1)
		session.typingSender.noteText("hello!!", in: conversation, at: now.addingTimeInterval(3))
		#expect(session.sentLines.count == 2)
	}

	@Test("The three-second limit also applies after paused and done notices", arguments: [TypingState.paused, .done])
	func rateLimitsStateChanges(_ state: TypingState) throws {
		let session = TestServerSession()
		session.markAsLoggedIn()
		session.enableCapability(.messageTags)
		session.environment.settings.sendTypingNotifications = true
		let conversation = try #require(session.findConversationOrCreate("alice", isDirect: true))
		conversation.activate()
		defer { session.cancelPendingSessionTasks() }
		let start = Date()
		session.typingSender.noteText("hello", in: conversation, at: start)
		if state == .paused {
			session.typingSender.pause(in: conversation, at: start.addingTimeInterval(5))
		} else {
			session.typingSender.finish(in: conversation, at: start.addingTimeInterval(5))
		}
		try #require(session.sentLines.count == 2)
		session.typingSender.noteText("again", in: conversation, at: start.addingTimeInterval(7.9))
		#expect(session.sentLines.count == 2)
		session.typingSender.noteText("again!", in: conversation, at: start.addingTimeInterval(8))
		#expect(session.sentLines.compactMap { $0 as? String } == [
			"@+typing=active TAGMSG alice",
			"@+typing=\(state.rawValue) TAGMSG alice",
			"@+typing=active TAGMSG alice",
		])
	}

	@Test("Clearing and immediately typing again preserves the cooldown")
	func quickClearDoesNotResetThrottle() throws {
		let session = TestServerSession()
		session.markAsLoggedIn()
		session.enableCapability(.messageTags)
		session.environment.settings.sendTypingNotifications = true
		let conversation = try #require(session.findConversationOrCreate("alice", isDirect: true))
		conversation.activate()
		defer { session.cancelPendingSessionTasks() }
		let start = Date()
		session.typingSender.noteText("hello", in: conversation, at: start)
		session.typingSender.noteText("", in: conversation, at: start.addingTimeInterval(1))
		session.typingSender.noteText("new", in: conversation, at: start.addingTimeInterval(2))
		#expect(session.sentLines.count == 1)
		session.typingSender.noteText("new!", in: conversation, at: start.addingTimeInterval(3))
		#expect(session.sentLines.count == 2)
	}
}
