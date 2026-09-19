// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing

/// Every event a `ChatSessionPresenting` can be told about, in the order it arrived.
enum RecordedDirectoryEvent: Equatable {
	case willBeginBulkUpdate
	case didEndBulkUpdate
	case addedSession(String, Int)
	case removedSession(String)
	case movedSession(Int, Int)
	case addedChannel(String, on: String, at: Int)
	case removedChannel(String, on: String)
	case movedChannel(on: String, from: Int, to: Int)
	case selectionRequested(String)
	case deselectionRequested(String)
	case groupDeselectionRequested(String)
	case selectionAdjustmentRequested
	case sessionListChanged
	case sidebarChanged
	case settingsChanged
}

@MainActor
final class RecordingDirectoryObserver: ChatSessionPresenting {
	private(set) var events: [RecordedDirectoryEvent] = []

	func chatSessionWillBeginBulkUpdate(_: ChatSession) {
		events.append(.willBeginBulkUpdate)
	}

	func chatSessionDidEndBulkUpdate(_: ChatSession) {
		events.append(.didEndBulkUpdate)
	}

	func chatSession(_: ChatSession, didAddSession session: ServerSession, at index: Int) {
		events.append(.addedSession(session.uniqueIdentifier, index))
	}

	func chatSession(_: ChatSession, didRemoveSession session: ServerSession) {
		events.append(.removedSession(session.uniqueIdentifier))
	}

	func chatSession(_: ChatSession, didMoveSessionFrom oldIndex: Int, to newIndex: Int) {
		events.append(.movedSession(oldIndex, newIndex))
	}

	func chatSession(_: ChatSession, didAddConversation channel: Conversation, on session: ServerSession, at index: Int) {
		events.append(.addedChannel(channel.name, on: session.uniqueIdentifier, at: index))
	}

	func chatSession(_: ChatSession, didRemoveConversation channel: Conversation, on session: ServerSession) {
		events.append(.removedChannel(channel.name, on: session.uniqueIdentifier))
	}

	func chatSession(_: ChatSession, didMoveConversationOn session: ServerSession, from oldIndex: Int, to newIndex: Int) {
		events.append(.movedChannel(on: session.uniqueIdentifier, from: oldIndex, to: newIndex))
	}

	func chatSession(_: ChatSession, requestsSelectionOf item: ChatItem) {
		events.append(.selectionRequested(item.uniqueIdentifier))
	}

	func chatSession(_: ChatSession, requestsDeselectionOf item: ChatItem) {
		events.append(.deselectionRequested(item.uniqueIdentifier))
	}

	func chatSession(_: ChatSession, requestsGroupDeselectionOf item: ChatItem) {
		events.append(.groupDeselectionRequested(item.uniqueIdentifier))
	}

	func chatSessionRequestsSelectionAdjustment(_: ChatSession) {
		events.append(.selectionAdjustmentRequested)
	}

	func chatSessionListDidChange(_: ChatSession) {
		events.append(.sessionListChanged)
	}

	func chatSessionSidebarDidChange(_: ChatSession) {
		events.append(.sidebarChanged)
	}

	func chatSessionSettingsDidChange(_: ChatSession) {
		events.append(.settingsChanged)
	}
}

/// Registers another observer the first time it hears the session list change.
@MainActor
private final class RegisteringDirectoryObserver: ChatSessionPresenting {
	let late = RecordingDirectoryObserver()
	private var registered = false

	func chatSessionListDidChange(_ chatSession: ChatSession) {
		guard registered == false else { return }
		registered = true
		chatSession.addObserver(late)
	}
}

@MainActor
private struct ChatSessionFixture {
	let fixture = ChatEnvironmentFixture()
	let observer = RecordingDirectoryObserver()

	var chatSession: ChatSession {
		fixture.chatSession
	}

	init() {
		chatSession.addObserver(observer)
	}

	func makeSession(named name: String) -> ServerSession {
		var config = ServerConfig()
		config.connectionName = name
		return chatSession.createSession(with: config)
	}
}

@MainActor
@Suite("Chat session presenting events")
struct ChatSessionPresentingTests {
	@Test("A created session is published with its index and refreshes the lists")
	func addingASessionPublishesIt() {
		let context = ChatSessionFixture()
		let session = context.makeSession(named: "First")

		#expect(context.observer.events.contains(.addedSession(session.uniqueIdentifier, 0)))
		#expect(context.observer.events.contains(.sessionListChanged))
		#expect(context.observer.events.contains(.sidebarChanged))
	}

	/// Registering from inside an event wrote to the observer list while the
	/// delivery loop held it, and the loop then restored the list it started
	/// with.
	@Test("An observer registered from inside an event is kept and hears the events after it")
	func observerRegisteredDuringDeliveryIsKept() {
		let context = ChatSessionFixture()
		let registering = RegisteringDirectoryObserver()
		context.chatSession.addObserver(registering)

		let first = context.makeSession(named: "First")
		#expect(registering.late.events.contains(.addedSession(first.uniqueIdentifier, 0)) == false)

		let second = context.makeSession(named: "Second")
		#expect(registering.late.events.contains(.addedSession(second.uniqueIdentifier, 1)))
	}

	@Test("The first session is the one the chat session asks to be selected")
	func firstSessionIsSelected() {
		let context = ChatSessionFixture()
		let first = context.makeSession(named: "First")
		let second = context.makeSession(named: "Second")

		#expect(context.observer.events.contains(.selectionRequested(first.uniqueIdentifier)))
		#expect(context.observer.events.contains(.selectionRequested(second.uniqueIdentifier)) == false)
	}

	@Test("Destroying a session deselects it, publishes the removal and refreshes the lists")
	func removingASessionPublishesIt() {
		let context = ChatSessionFixture()
		let session = context.makeSession(named: "First")
		let identifier = session.uniqueIdentifier

		context.chatSession.destroySession(session)

		let events = context.observer.events
		#expect(events.contains(.groupDeselectionRequested(identifier)))
		#expect(events.contains(.removedSession(identifier)))
		#expect(context.chatSession.sessions.isEmpty)
	}

	@Test("A session is deselected before it is removed")
	func deselectionPrecedesRemoval() throws {
		let context = ChatSessionFixture()
		let session = context.makeSession(named: "First")
		let identifier = session.uniqueIdentifier

		context.chatSession.destroySession(session)

		let events = context.observer.events
		let deselected = try #require(events.firstIndex(of: .groupDeselectionRequested(identifier)))
		let removed = try #require(events.firstIndex(of: .removedSession(identifier)))
		#expect(deselected < removed)
	}

	@Test("Reordering sessions publishes the move and the new order")
	func movingASessionPublishesIt() {
		let context = ChatSessionFixture()
		let first = context.makeSession(named: "First")
		let second = context.makeSession(named: "Second")

		context.chatSession.moveSession(from: 1, to: 0)

		#expect(context.observer.events.contains(.movedSession(1, 0)))
		#expect(context.chatSession.sessions.map(\.uniqueIdentifier) == [
			second.uniqueIdentifier, first.uniqueIdentifier,
		])
	}

	@Test("A move to an index that does not exist changes nothing")
	func movingAMissingSessionIsIgnored() {
		let context = ChatSessionFixture()
		_ = context.makeSession(named: "First")

		context.chatSession.moveSession(from: 4, to: 0)

		#expect(context.observer.events.contains { event in
			if case .movedSession = event {
				return true
			}
			return false
		} == false)
	}

	@Test("A created channel is published with its index and adjusts the selection")
	func addingAChannelPublishesIt() {
		let context = ChatSessionFixture()
		let session = context.makeSession(named: "First")

		let channel = context.chatSession.createConversation(with: ConversationConfig.seed(withName: "#one"), on: session)

		#expect(context.observer.events.contains(
			.addedChannel(channel.name, on: session.uniqueIdentifier, at: 0)
		))
		#expect(context.observer.events.contains(.selectionAdjustmentRequested))
	}

	@Test("Destroying a channel publishes the removal and drops it from the session")
	func removingAChannelPublishesIt() {
		let context = ChatSessionFixture()
		let session = context.makeSession(named: "First")
		let channel = context.chatSession.createConversation(with: ConversationConfig.seed(withName: "#one"), on: session)

		context.chatSession.destroyConversation(channel, options: [.reloadsSidebar])

		#expect(context.observer.events.contains(
			.removedChannel("#one", on: session.uniqueIdentifier)
		))
		#expect(session.conversationList.isEmpty)
	}

	@Test("A channel destroyed without a redraw still leaves its session")
	func removingAChannelWithoutReloadStillDropsItFromTheSession() {
		let context = ChatSessionFixture()
		let session = context.makeSession(named: "First")
		let channel = context.chatSession.createConversation(with: ConversationConfig.seed(withName: "#one"), on: session)

		context.chatSession.destroyConversation(channel, options: [])

		#expect(session.conversationList.isEmpty)
		// Removal releases the controller even when redraw is batched.
		#expect(context.observer.events.contains(
			.removedChannel("#one", on: session.uniqueIdentifier)
		))
	}

	@Test("A move past the end reports the position the session landed at")
	func movingASessionPastTheEndReportsTheClampedIndex() {
		let context = ChatSessionFixture()
		let first = context.makeSession(named: "First")
		let second = context.makeSession(named: "Second")

		context.chatSession.moveSession(from: 0, to: 9)

		#expect(context.observer.events.contains(.movedSession(0, 1)))
		#expect(context.observer.events.contains(.movedSession(0, 9)) == false)
		#expect(context.chatSession.sessions.map(\.uniqueIdentifier) == [
			second.uniqueIdentifier, first.uniqueIdentifier,
		])
	}

	@Test("A channel move past the end reports the position the channel landed at")
	func movingAChannelPastTheEndReportsTheClampedIndex() {
		let context = ChatSessionFixture()
		let session = context.makeSession(named: "First")
		_ = context.chatSession.createConversation(with: ConversationConfig.seed(withName: "#one"), on: session)
		_ = context.chatSession.createConversation(with: ConversationConfig.seed(withName: "#two"), on: session)

		context.chatSession.moveConversation(on: session, from: 0, to: 9)

		#expect(context.observer.events.contains(
			.movedChannel(on: session.uniqueIdentifier, from: 0, to: 1)
		))
		#expect(session.conversationList.map(\.name) == ["#two", "#one"])
	}

	@Test("An observer that has gone is forgotten, and the rest still hear")
	func deallocatedObserversAreDropped() {
		let context = ChatSessionFixture()
		weak var weakTransient: RecordingDirectoryObserver?

		do {
			let transient = RecordingDirectoryObserver()
			weakTransient = transient
			context.chatSession.addObserver(transient)
		}

		#expect(weakTransient == nil)

		let session = context.makeSession(named: "First")
		#expect(context.observer.events.contains(.addedSession(session.uniqueIdentifier, 0)))
	}

	@Test("Removing an observer stops the events")
	func removedObserversAreNotTold() {
		let context = ChatSessionFixture()
		context.chatSession.removeObserver(context.observer)

		_ = context.makeSession(named: "First")

		#expect(context.observer.events.isEmpty)
	}
}
