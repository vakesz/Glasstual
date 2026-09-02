/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 *
 *  * Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 *  * Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 *  * Neither the name of Textual and/or Codeux Software, nor the names of
 *    its contributors may be used to endorse or promote products derived
 *    from this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED. IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
 * FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
 * OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
 * LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
 * OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
 * SUCH DAMAGE.
 *
 *********************************************************************** */

import Foundation
@testable import Glasstual
import Testing

/// Every event a `WorldObserver` can be told about, in the order it arrived.
enum RecordedWorldEvent: Equatable {
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
final class RecordingWorldObserver: WorldObserver {
	private(set) var events: [RecordedWorldEvent] = []

	func worldWillBeginBulkUpdate(_: IRCWorld) {
		events.append(.willBeginBulkUpdate)
	}

	func worldDidEndBulkUpdate(_: IRCWorld) {
		events.append(.didEndBulkUpdate)
	}

	func world(_: IRCWorld, didAddClient client: IRCClient, at index: Int) {
		events.append(.addedClient(client.uniqueIdentifier, index))
	}

	func world(_: IRCWorld, didRemoveClient client: IRCClient) {
		events.append(.removedClient(client.uniqueIdentifier))
	}

	func world(_: IRCWorld, didMoveClientFrom oldIndex: Int, to newIndex: Int) {
		events.append(.movedClient(oldIndex, newIndex))
	}

	func world(_: IRCWorld, didAddChannel channel: IRCChannel, on client: IRCClient, at index: Int) {
		events.append(.addedChannel(channel.name, on: client.uniqueIdentifier, at: index))
	}

	func world(_: IRCWorld, didRemoveChannel channel: IRCChannel, on client: IRCClient) {
		events.append(.removedChannel(channel.name, on: client.uniqueIdentifier))
	}

	func world(_: IRCWorld, didMoveChannelOn client: IRCClient, from oldIndex: Int, to newIndex: Int) {
		events.append(.movedChannel(on: client.uniqueIdentifier, from: oldIndex, to: newIndex))
	}

	func world(_: IRCWorld, requestsSelectionOf item: IRCTreeItem) {
		events.append(.selectionRequested(item.uniqueIdentifier))
	}

	func world(_: IRCWorld, requestsDeselectionOf item: IRCTreeItem) {
		events.append(.deselectionRequested(item.uniqueIdentifier))
	}

	func world(_: IRCWorld, requestsGroupDeselectionOf item: IRCTreeItem) {
		events.append(.groupDeselectionRequested(item.uniqueIdentifier))
	}

	func worldRequestsSelectionAdjustment(_: IRCWorld) {
		events.append(.selectionAdjustmentRequested)
	}

	func worldClientListDidChange(_: IRCWorld) {
		events.append(.clientListChanged)
	}

	func worldNavigationListDidChange(_: IRCWorld) {
		events.append(.navigationListChanged)
	}

	func worldPreferencesDidChange(_: IRCWorld) {
		events.append(.preferencesChanged)
	}
}

@MainActor
private struct WorldFixture {
	let fixture = GLTClientEnvironmentFixture()
	let observer = RecordingWorldObserver()

	var world: IRCWorld {
		fixture.world
	}

	init() {
		world.addObserver(observer)
	}

	func makeClient(named name: String) -> IRCClient {
		var config = ClientConfig()
		config.connectionName = name
		return world.createClient(with: config)
	}
}

@MainActor
@Suite("World observer events")
struct WorldObserverTests {
	@Test("A created client is published with its index and refreshes the lists")
	func addingAClientPublishesIt() {
		let context = WorldFixture()
		let client = context.makeClient(named: "First")

		#expect(context.observer.events.contains(.addedClient(client.uniqueIdentifier, 0)))
		#expect(context.observer.events.contains(.clientListChanged))
		#expect(context.observer.events.contains(.navigationListChanged))
	}

	@Test("The first client is the one the world asks to be selected")
	func firstClientIsSelected() {
		let context = WorldFixture()
		let first = context.makeClient(named: "First")
		let second = context.makeClient(named: "Second")

		#expect(context.observer.events.contains(.selectionRequested(first.uniqueIdentifier)))
		#expect(context.observer.events.contains(.selectionRequested(second.uniqueIdentifier)) == false)
	}

	@Test("Destroying a client deselects it, publishes the removal and refreshes the lists")
	func removingAClientPublishesIt() {
		let context = WorldFixture()
		let client = context.makeClient(named: "First")
		let identifier = client.uniqueIdentifier

		context.world.destroyClient(client)

		let events = context.observer.events
		#expect(events.contains(.groupDeselectionRequested(identifier)))
		#expect(events.contains(.removedClient(identifier)))
		#expect(context.world.clientList.isEmpty)
	}

	@Test("A client is deselected before it is removed")
	func deselectionPrecedesRemoval() throws {
		let context = WorldFixture()
		let client = context.makeClient(named: "First")
		let identifier = client.uniqueIdentifier

		context.world.destroyClient(client)

		let events = context.observer.events
		let deselected = try #require(events.firstIndex(of: .groupDeselectionRequested(identifier)))
		let removed = try #require(events.firstIndex(of: .removedClient(identifier)))
		#expect(deselected < removed)
	}

	@Test("Reordering clients publishes the move and the new order")
	func movingAClientPublishesIt() {
		let context = WorldFixture()
		let first = context.makeClient(named: "First")
		let second = context.makeClient(named: "Second")

		context.world.moveClient(from: 1, to: 0)

		#expect(context.observer.events.contains(.movedClient(1, 0)))
		#expect(context.world.clientList.map(\.uniqueIdentifier) == [
			second.uniqueIdentifier, first.uniqueIdentifier,
		])
	}

	@Test("A move to an index that does not exist changes nothing")
	func movingAMissingClientIsIgnored() {
		let context = WorldFixture()
		_ = context.makeClient(named: "First")

		context.world.moveClient(from: 4, to: 0)

		#expect(context.observer.events.contains { event in
			if case .movedClient = event {
				return true
			}
			return false
		} == false)
	}

	@Test("A created channel is published with its index and adjusts the selection")
	func addingAChannelPublishesIt() {
		let context = WorldFixture()
		let client = context.makeClient(named: "First")

		let channel = context.world.createChannel(with: ChannelConfig.seed(withName: "#one"), on: client)

		#expect(context.observer.events.contains(
			.addedChannel(channel.name, on: client.uniqueIdentifier, at: 0)
		))
		#expect(context.observer.events.contains(.selectionAdjustmentRequested))
	}

	@Test("Destroying a channel publishes the removal and drops it from the client")
	func removingAChannelPublishesIt() {
		let context = WorldFixture()
		let client = context.makeClient(named: "First")
		let channel = context.world.createChannel(with: ChannelConfig.seed(withName: "#one"), on: client)

		context.world.destroyChannel(channel, reload: true, part: false)

		#expect(context.observer.events.contains(
			.removedChannel("#one", on: client.uniqueIdentifier)
		))
		#expect(client.channelList.isEmpty)
	}

	@Test("A channel destroyed without a redraw still leaves its client")
	func removingAChannelWithoutReloadStillDropsItFromTheClient() {
		let context = WorldFixture()
		let client = context.makeClient(named: "First")
		let channel = context.world.createChannel(with: ChannelConfig.seed(withName: "#one"), on: client)

		context.world.destroyChannel(channel, reload: false, part: false)

		#expect(client.channelList.isEmpty)
		#expect(context.observer.events.contains(
			.removedChannel("#one", on: client.uniqueIdentifier)
		) == false)
	}

	@Test("A move past the end reports the position the client landed at")
	func movingAClientPastTheEndReportsTheClampedIndex() {
		let context = WorldFixture()
		let first = context.makeClient(named: "First")
		let second = context.makeClient(named: "Second")

		context.world.moveClient(from: 0, to: 9)

		#expect(context.observer.events.contains(.movedClient(0, 1)))
		#expect(context.observer.events.contains(.movedClient(0, 9)) == false)
		#expect(context.world.clientList.map(\.uniqueIdentifier) == [
			second.uniqueIdentifier, first.uniqueIdentifier,
		])
	}

	@Test("A channel move past the end reports the position the channel landed at")
	func movingAChannelPastTheEndReportsTheClampedIndex() {
		let context = WorldFixture()
		let client = context.makeClient(named: "First")
		_ = context.world.createChannel(with: ChannelConfig.seed(withName: "#one"), on: client)
		_ = context.world.createChannel(with: ChannelConfig.seed(withName: "#two"), on: client)

		context.world.moveChannel(on: client, from: 0, to: 9)

		#expect(context.observer.events.contains(
			.movedChannel(on: client.uniqueIdentifier, from: 0, to: 1)
		))
		#expect(client.channelList.map(\.name) == ["#two", "#one"])
	}

	@Test("Reordering channels publishes the move and the new order")
	func movingAChannelPublishesIt() {
		let context = WorldFixture()
		let client = context.makeClient(named: "First")
		_ = context.world.createChannel(with: ChannelConfig.seed(withName: "#one"), on: client)
		_ = context.world.createChannel(with: ChannelConfig.seed(withName: "#two"), on: client)

		context.world.moveChannel(on: client, from: 0, to: 1)

		#expect(context.observer.events.contains(
			.movedChannel(on: client.uniqueIdentifier, from: 0, to: 1)
		))
		#expect(client.channelList.map(\.name) == ["#two", "#one"])
	}

	@Test("An observer that has gone is forgotten, and the rest still hear")
	func deallocatedObserversAreDropped() {
		let context = WorldFixture()
		weak var weakTransient: RecordingWorldObserver?

		do {
			let transient = RecordingWorldObserver()
			weakTransient = transient
			context.world.addObserver(transient)
		}

		#expect(weakTransient == nil)

		let client = context.makeClient(named: "First")
		#expect(context.observer.events.contains(.addedClient(client.uniqueIdentifier, 0)))
	}

	@Test("Removing an observer stops the events")
	func removedObserversAreNotTold() {
		let context = WorldFixture()
		context.world.removeObserver(context.observer)

		_ = context.makeClient(named: "First")

		#expect(context.observer.events.isEmpty)
	}
}
