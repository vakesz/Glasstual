// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing

/// Every event a `ClientDirectoryObserver` can be told about, in the order it arrived.
enum RecordedDirectoryEvent: Equatable {
	case willBeginBulkUpdate
	case didEndBulkUpdate
	case addedClient(String, Int)
	case removedClient(String)
	case movedClient(Int, Int)
	case addedChannel(String, on: String, at: Int)
	case removedChannel(String, on: String)
	case movedChannel(on: String, from: Int, to: Int)
	case selectionRequested(String)
	case deselectionRequested(String)
	case groupDeselectionRequested(String)
	case selectionAdjustmentRequested
	case clientListChanged
	case navigationListChanged
	case preferencesChanged
}

@MainActor
final class RecordingDirectoryObserver: ClientDirectoryObserver {
	private(set) var events: [RecordedDirectoryEvent] = []

	func clientDirectoryWillBeginBulkUpdate(_: ClientDirectory) {
		events.append(.willBeginBulkUpdate)
	}

	func clientDirectoryDidEndBulkUpdate(_: ClientDirectory) {
		events.append(.didEndBulkUpdate)
	}

	func clientDirectory(_: ClientDirectory, didAddClient client: Client, at index: Int) {
		events.append(.addedClient(client.uniqueIdentifier, index))
	}

	func clientDirectory(_: ClientDirectory, didRemoveClient client: Client) {
		events.append(.removedClient(client.uniqueIdentifier))
	}

	func clientDirectory(_: ClientDirectory, didMoveClientFrom oldIndex: Int, to newIndex: Int) {
		events.append(.movedClient(oldIndex, newIndex))
	}

	func clientDirectory(_: ClientDirectory, didAddChannel channel: Channel, on client: Client, at index: Int) {
		events.append(.addedChannel(channel.name, on: client.uniqueIdentifier, at: index))
	}

	func clientDirectory(_: ClientDirectory, didRemoveChannel channel: Channel, on client: Client) {
		events.append(.removedChannel(channel.name, on: client.uniqueIdentifier))
	}

	func clientDirectory(_: ClientDirectory, didMoveChannelOn client: Client, from oldIndex: Int, to newIndex: Int) {
		events.append(.movedChannel(on: client.uniqueIdentifier, from: oldIndex, to: newIndex))
	}

	func clientDirectory(_: ClientDirectory, requestsSelectionOf item: ChatItem) {
		events.append(.selectionRequested(item.uniqueIdentifier))
	}

	func clientDirectory(_: ClientDirectory, requestsDeselectionOf item: ChatItem) {
		events.append(.deselectionRequested(item.uniqueIdentifier))
	}

	func clientDirectory(_: ClientDirectory, requestsGroupDeselectionOf item: ChatItem) {
		events.append(.groupDeselectionRequested(item.uniqueIdentifier))
	}

	func clientDirectoryRequestsSelectionAdjustment(_: ClientDirectory) {
		events.append(.selectionAdjustmentRequested)
	}

	func clientDirectoryClientListDidChange(_: ClientDirectory) {
		events.append(.clientListChanged)
	}

	func clientDirectoryNavigationListDidChange(_: ClientDirectory) {
		events.append(.navigationListChanged)
	}

	func clientDirectoryPreferencesDidChange(_: ClientDirectory) {
		events.append(.preferencesChanged)
	}
}

/// Registers another observer the first time it hears the client list change.
@MainActor
private final class RegisteringDirectoryObserver: ClientDirectoryObserver {
	let late = RecordingDirectoryObserver()
	private var registered = false

	func clientDirectoryClientListDidChange(_ world: ClientDirectory) {
		guard registered == false else { return }
		registered = true
		world.addObserver(late)
	}
}

@MainActor
private struct ClientDirectoryFixture {
	let fixture = ClientEnvironmentFixture()
	let observer = RecordingDirectoryObserver()

	var clientDirectory: ClientDirectory {
		fixture.clientDirectory
	}

	init() {
		clientDirectory.addObserver(observer)
	}

	func makeClient(named name: String) -> Client {
		var config = ClientConfig()
		config.connectionName = name
		return clientDirectory.createClient(with: config)
	}
}

@MainActor
@Suite("Client directory observer events")
struct ClientDirectoryObserverTests {
	@Test("A created client is published with its index and refreshes the lists")
	func addingAClientPublishesIt() {
		let context = ClientDirectoryFixture()
		let client = context.makeClient(named: "First")

		#expect(context.observer.events.contains(.addedClient(client.uniqueIdentifier, 0)))
		#expect(context.observer.events.contains(.clientListChanged))
		#expect(context.observer.events.contains(.navigationListChanged))
	}

	/// Registering from inside an event wrote to the observer list while the
	/// delivery loop held it, and the loop then restored the list it started
	/// with.
	@Test("An observer registered from inside an event is kept and hears the events after it")
	func observerRegisteredDuringDeliveryIsKept() {
		let context = ClientDirectoryFixture()
		let registering = RegisteringDirectoryObserver()
		context.clientDirectory.addObserver(registering)

		let first = context.makeClient(named: "First")
		#expect(registering.late.events.contains(.addedClient(first.uniqueIdentifier, 0)) == false)

		let second = context.makeClient(named: "Second")
		#expect(registering.late.events.contains(.addedClient(second.uniqueIdentifier, 1)))
	}

	@Test("The first client is the one the world asks to be selected")
	func firstClientIsSelected() {
		let context = ClientDirectoryFixture()
		let first = context.makeClient(named: "First")
		let second = context.makeClient(named: "Second")

		#expect(context.observer.events.contains(.selectionRequested(first.uniqueIdentifier)))
		#expect(context.observer.events.contains(.selectionRequested(second.uniqueIdentifier)) == false)
	}

	@Test("Destroying a client deselects it, publishes the removal and refreshes the lists")
	func removingAClientPublishesIt() {
		let context = ClientDirectoryFixture()
		let client = context.makeClient(named: "First")
		let identifier = client.uniqueIdentifier

		context.clientDirectory.destroyClient(client)

		let events = context.observer.events
		#expect(events.contains(.groupDeselectionRequested(identifier)))
		#expect(events.contains(.removedClient(identifier)))
		#expect(context.clientDirectory.clientList.isEmpty)
	}

	@Test("A client is deselected before it is removed")
	func deselectionPrecedesRemoval() throws {
		let context = ClientDirectoryFixture()
		let client = context.makeClient(named: "First")
		let identifier = client.uniqueIdentifier

		context.clientDirectory.destroyClient(client)

		let events = context.observer.events
		let deselected = try #require(events.firstIndex(of: .groupDeselectionRequested(identifier)))
		let removed = try #require(events.firstIndex(of: .removedClient(identifier)))
		#expect(deselected < removed)
	}

	@Test("Reordering clients publishes the move and the new order")
	func movingAClientPublishesIt() {
		let context = ClientDirectoryFixture()
		let first = context.makeClient(named: "First")
		let second = context.makeClient(named: "Second")

		context.clientDirectory.moveClient(from: 1, to: 0)

		#expect(context.observer.events.contains(.movedClient(1, 0)))
		#expect(context.clientDirectory.clientList.map(\.uniqueIdentifier) == [
			second.uniqueIdentifier, first.uniqueIdentifier,
		])
	}

	@Test("A move to an index that does not exist changes nothing")
	func movingAMissingClientIsIgnored() {
		let context = ClientDirectoryFixture()
		_ = context.makeClient(named: "First")

		context.clientDirectory.moveClient(from: 4, to: 0)

		#expect(context.observer.events.contains { event in
			if case .movedClient = event {
				return true
			}
			return false
		} == false)
	}

	@Test("A created channel is published with its index and adjusts the selection")
	func addingAChannelPublishesIt() {
		let context = ClientDirectoryFixture()
		let client = context.makeClient(named: "First")

		let channel = context.clientDirectory.createChannel(with: ChannelConfig.seed(withName: "#one"), on: client)

		#expect(context.observer.events.contains(
			.addedChannel(channel.name, on: client.uniqueIdentifier, at: 0)
		))
		#expect(context.observer.events.contains(.selectionAdjustmentRequested))
	}

	@Test("Destroying a channel publishes the removal and drops it from the client")
	func removingAChannelPublishesIt() {
		let context = ClientDirectoryFixture()
		let client = context.makeClient(named: "First")
		let channel = context.clientDirectory.createChannel(with: ChannelConfig.seed(withName: "#one"), on: client)

		context.clientDirectory.destroyChannel(channel, options: [.reloadsNavigationList])

		#expect(context.observer.events.contains(
			.removedChannel("#one", on: client.uniqueIdentifier)
		))
		#expect(client.channelList.isEmpty)
	}

	@Test("A channel destroyed without a redraw still leaves its client")
	func removingAChannelWithoutReloadStillDropsItFromTheClient() {
		let context = ClientDirectoryFixture()
		let client = context.makeClient(named: "First")
		let channel = context.clientDirectory.createChannel(with: ChannelConfig.seed(withName: "#one"), on: client)

		context.clientDirectory.destroyChannel(channel, options: [])

		#expect(client.channelList.isEmpty)
		// Removal releases the controller even when redraw is batched.
		#expect(context.observer.events.contains(
			.removedChannel("#one", on: client.uniqueIdentifier)
		))
	}

	@Test("A move past the end reports the position the client landed at")
	func movingAClientPastTheEndReportsTheClampedIndex() {
		let context = ClientDirectoryFixture()
		let first = context.makeClient(named: "First")
		let second = context.makeClient(named: "Second")

		context.clientDirectory.moveClient(from: 0, to: 9)

		#expect(context.observer.events.contains(.movedClient(0, 1)))
		#expect(context.observer.events.contains(.movedClient(0, 9)) == false)
		#expect(context.clientDirectory.clientList.map(\.uniqueIdentifier) == [
			second.uniqueIdentifier, first.uniqueIdentifier,
		])
	}

	@Test("A channel move past the end reports the position the channel landed at")
	func movingAChannelPastTheEndReportsTheClampedIndex() {
		let context = ClientDirectoryFixture()
		let client = context.makeClient(named: "First")
		_ = context.clientDirectory.createChannel(with: ChannelConfig.seed(withName: "#one"), on: client)
		_ = context.clientDirectory.createChannel(with: ChannelConfig.seed(withName: "#two"), on: client)

		context.clientDirectory.moveChannel(on: client, from: 0, to: 9)

		#expect(context.observer.events.contains(
			.movedChannel(on: client.uniqueIdentifier, from: 0, to: 1)
		))
		#expect(client.channelList.map(\.name) == ["#two", "#one"])
	}

	@Test("An observer that has gone is forgotten, and the rest still hear")
	func deallocatedObserversAreDropped() {
		let context = ClientDirectoryFixture()
		weak var weakTransient: RecordingDirectoryObserver?

		do {
			let transient = RecordingDirectoryObserver()
			weakTransient = transient
			context.clientDirectory.addObserver(transient)
		}

		#expect(weakTransient == nil)

		let client = context.makeClient(named: "First")
		#expect(context.observer.events.contains(.addedClient(client.uniqueIdentifier, 0)))
	}

	@Test("Removing an observer stops the events")
	func removedObserversAreNotTold() {
		let context = ClientDirectoryFixture()
		context.clientDirectory.removeObserver(context.observer)

		_ = context.makeClient(named: "First")

		#expect(context.observer.events.isEmpty)
	}
}
